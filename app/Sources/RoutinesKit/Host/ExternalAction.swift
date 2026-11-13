import Foundation

/// A plugin action or a transition that another program asks for, for example a script: `routines://perform?plugin=&action=&item=&text=&reply=`.
public struct ExternalAction: Equatable, Sendable {
    public static let scheme = "routines"
    public static let flag = "--perform"

    public var pluginId: String
    public var actionId: String
    /// The actionable of a transition. Without it, the request is a plugin action.
    public var item: String?
    public var text: String?
    /// The file where the app writes the answer, so the caller can print it.
    public var replyFile: String?

    public init(pluginId: String, actionId: String, item: String? = nil, text: String?, replyFile: String?) {
        self.pluginId = pluginId
        self.actionId = actionId
        self.item = item
        self.text = text
        self.replyFile = replyFile
    }

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        parts.host = "perform"
        parts.queryItems = [URLQueryItem(name: "plugin", value: pluginId), URLQueryItem(name: "action", value: actionId)] + [item.map { URLQueryItem(name: "item", value: $0) }, text.map { URLQueryItem(name: "text", value: $0) }, replyFile.map { URLQueryItem(name: "reply", value: $0) }].compactMap { $0 }
        return parts.url!
    }

    public static func parse(_ url: URL) -> ExternalAction? {
        guard url.scheme == scheme, url.host() == "perform", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let value = { (name: String) in items.first { $0.name == name }?.value }
        guard let plugin = value("plugin"), let action = value("action") else { return nil }
        return ExternalAction(pluginId: plugin, actionId: action, item: value("item"), text: value("text"), replyFile: value("reply"))
    }

    /// An answer goes only to the replies folder of the app. The policy checks the rest, as for each other caller.
    public func checkReply(repliesDir: String) -> Result<Void, HostError> {
        guard let replyFile else { return .success(()) }
        let resolved = (replyFile as NSString).standardizingPath
        return resolved.hasPrefix(repliesDir + "/") ? .success(()) : .failure(.denied("the reply file must be in \(repliesDir)"))
    }

    /// With an item, a transition trigger with the source `external`. Without one, a plugin action.
    public func trigger(at date: Date) -> Trigger {
        guard let item else { return Trigger(routine: pluginId, source: .external, work: .action, transition: actionId, text: text, at: date) }
        return .transition(actionId, of: item, routine: pluginId, source: .external, text: text, at: date)
    }
}
