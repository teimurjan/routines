import Foundation

/// An action that the host found by its id, with the title for the confirmation dialog.
public struct ResolvedAction: Equatable, Sendable {
    public var action: CardAction
    /// The title of the stored card, or nil for a menu action.
    public var cardTitle: String?

    public init(action: CardAction, cardTitle: String?) {
        self.action = action
        self.cardTitle = cardTitle
    }
}

/// The host trusts no caller with an action. It finds the action in the manifest and checks its target. See specs/003-custom-ui-everywhere/contracts/actions.md.
public enum ActionLookup {
    /// A `cardId` asks for an item action. A nil `cardId` asks for a plugin action. `card` is the stored item with that id, if the plugin has one.
    public static func resolve(actionId: String, cardId: String?, pluginId: String, manifest: Manifest, card: Card?) -> Result<ResolvedAction, HostError> {
        guard let action = manifest.actions.first(where: { $0.id == actionId }) else { return .failure(.denied("\(pluginId) has no action \(actionId)")) }
        guard let cardId else {
            return action.isItemAction ? .failure(.denied("\(actionId) needs an item")) : .success(ResolvedAction(action: action, cardTitle: nil))
        }
        guard action.isItemAction else { return .failure(.denied("\(actionId) is not an item action")) }
        guard let card else { return .failure(.denied("\(pluginId) has no card \(cardId)")) }
        return .success(ResolvedAction(action: action, cardTitle: card.title))
    }

    /// An action with `input` needs text that is not blank.
    public static func checkText(_ action: CardAction, text: String?) -> Result<Void, HostError> {
        guard action.input != nil else { return .success(()) }
        let blank = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return blank ? .failure(.failed("the action \(action.label) needs text")) : .success(())
    }
}
