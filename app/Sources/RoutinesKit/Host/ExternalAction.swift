import Foundation

/// A menu action that another program asks for, for example a script: `routines://perform?plugin=&action=&text=&reply=`.
public struct ExternalAction: Equatable, Sendable {
    public static let scheme = "routines"
    public static let flag = "--perform"

    public var pluginId: String
    public var actionId: String
    public var text: String?
    /// The file where the app writes the answer, so the caller can print it.
    public var replyFile: String?

    public init(pluginId: String, actionId: String, text: String?, replyFile: String?) {
        self.pluginId = pluginId
        self.actionId = actionId
        self.text = text
        self.replyFile = replyFile
    }

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        parts.host = "perform"
        parts.queryItems = [URLQueryItem(name: "plugin", value: pluginId), URLQueryItem(name: "action", value: actionId)] + [text.map { URLQueryItem(name: "text", value: $0) }, replyFile.map { URLQueryItem(name: "reply", value: $0) }].compactMap { $0 }
        return parts.url!
    }

    public static func parse(_ url: URL) -> ExternalAction? {
        guard url.scheme == scheme, url.host() == "perform", let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let value = { (name: String) in items.first { $0.name == name }?.value }
        guard let plugin = value("plugin"), let action = value("action") else { return nil }
        return ExternalAction(pluginId: plugin, actionId: action, text: value("text"), replyFile: value("reply"))
    }

    /// Only a plugin action that the manifest lists runs, and an answer goes only to the replies folder of the app.
    public func check(_ manifest: Manifest, repliesDir: String) -> Result<Void, HostError> {
        guard manifest.permissions.external.contains(actionId), let action = manifest.actions.first(where: { $0.id == actionId }) else {
            return .failure(.denied("\(pluginId) does not allow \(actionId) from outside the app"))
        }
        // Another program names no item, so it can start only a plugin action.
        if action.isItemAction { return .failure(.denied("\(actionId) needs an item")) }
        if let replyFile {
            let resolved = (replyFile as NSString).standardizingPath
            guard resolved.hasPrefix(repliesDir + "/") else { return .failure(.denied("the reply file must be in \(repliesDir)")) }
        }
        return .success(())
    }
}
