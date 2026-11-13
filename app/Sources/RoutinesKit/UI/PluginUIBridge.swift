import Foundation

/// An action that a page asked for, after the host found it on the stored card or in the manifest.
public struct PluginUIAction: Equatable, Sendable {
    public var action: CardAction
    /// Nil for a menu action.
    public var cardId: String?
    public var text: String?
    /// Set for a transition of an actionable. `action` then holds its label and style for the dialog.
    public var actionableId: String?

    public init(action: CardAction, cardId: String?, text: String?, actionableId: String? = nil) {
        self.action = action
        self.cardId = cardId
        self.text = text
        self.actionableId = actionableId
    }
}

/// What the app does with one message of a page. See "Bridge message and decision" in specs/002-plugin-ui/data-model.md.
public enum PluginUIDecision: Equatable, Sendable {
    /// Answer at once with this JSON value.
    case reply(String)
    /// The page sent `ready`, so the app shows it. The answer is null.
    case ready
    case refuse(String)
    case perform(PluginUIAction)
    /// Like `perform`, but the app asks you first. `title` is the stored card title, or the plugin name for a menu action.
    case confirm(PluginUIAction, title: String)
    /// Open an `http` or `https` URL in the default browser. The answer is null.
    case open(URL)
}

/// Decodes the messages of one plugin page. The page cannot name another plugin, because the bridge knows its plugin id.
public struct PluginUIBridge: Sendable {
    public let pluginId: String

    public init(pluginId: String) {
        self.pluginId = pluginId
    }

    private struct Message: Decodable {
        var type: String
        var cardId: String?
        var actionId: String?
        var text: String?
        var url: String?
        var actionable: String?
        var transition: String?
    }

    /// `card` finds a stored card of this plugin, and `actionable` an actionable that it owns. `snapshot` is the JSON of the current snapshot.
    public func decide(
        _ body: Data, manifest: Manifest, card: (String) -> Card?, actionable: (String) -> Actionable? = { _ in nil }, snapshot: () -> String
    ) -> PluginUIDecision {
        guard let message = try? Reply.decoder.decode(Message.self, from: body) else { return .refuse("the message must be an object with a type") }
        switch message.type {
        case "ready": return .ready
        case "snapshot": return .reply(snapshot())
        case "openLink": return openLink(message.url)
        case "perform":
            guard let cardId = message.cardId else { return .refuse("perform needs a cardId") }
            return action(message, cardId: cardId, manifest: manifest, card: card(cardId))
        case "performPluginAction": return action(message, cardId: nil, manifest: manifest, card: nil)
        case "transition": return transition(message, manifest: manifest, actionable: message.actionable.flatMap(actionable))
        default: return .refuse("unknown message type \(message.type)")
        }
    }

    private func openLink(_ text: String?) -> PluginUIDecision {
        guard let text, let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil else {
            return .refuse("only an http or https link opens")
        }
        return .open(url)
    }

    /// The page names the transition by id. The label, the style and the dialog come from the manifest and the stored title.
    private func transition(_ message: Message, manifest: Manifest, actionable: Actionable?) -> PluginUIDecision {
        guard let id = message.transition else { return .refuse("the message needs a transition") }
        guard let actionable, actionable.owner == pluginId else { return .refuse(Refusal.noActionable(message.actionable ?? "").description) }
        guard let declaration = manifest.transition(id) else { return .refuse(Refusal.noTransition(routine: pluginId, transition: id).description) }
        if declaration.input != nil, Policy.isBlank(message.text) { return .refuse(Refusal.needsText(label: declaration.label).description) }
        let button = CardAction(id: id, label: declaration.label, style: declaration.style, input: declaration.input, confirm: declaration.confirm, target: .item)
        let request = PluginUIAction(action: button, cardId: nil, text: message.text, actionableId: actionable.id)
        return declaration.needsConfirmation ? .confirm(request, title: actionable.title) : .perform(request)
    }

    private func action(_ message: Message, cardId: String?, manifest: Manifest, card: Card?) -> PluginUIDecision {
        guard let actionId = message.actionId else { return .refuse("the message needs an actionId") }
        let resolved = ActionLookup.resolve(actionId: actionId, cardId: cardId, pluginId: pluginId, manifest: manifest, card: card)
        switch resolved.flatMap({ found in ActionLookup.checkText(found.action, text: message.text).map { found } }) {
        case .failure(let error): return .refuse(error.description)
        case .success(let found):
            let request = PluginUIAction(action: found.action, cardId: cardId, text: message.text)
            return found.action.needsConfirmation ? .confirm(request, title: found.cardTitle ?? manifest.name) : .perform(request)
        }
    }
}
