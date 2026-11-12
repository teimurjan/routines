import Foundation

/// What a plugin UI gets from `snapshot` and from each `snapshot` event. See "Plugin UI snapshot" in specs/002-plugin-ui/data-model.md.
public struct PluginUISnapshot: Encodable, Equatable, Sendable {
    public struct Plugin: Encodable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var emoji: String?
        public var color: String
    }

    public struct Pending: Encodable, Equatable, Sendable {
        /// The ids of the items with an action in flight.
        public var items: [String]
        /// A menu action of the plugin is in flight.
        public var plugin: Bool
    }

    public struct Appearance: Encodable, Equatable, Sendable {
        public enum Scheme: String, Encodable, Sendable { case light, dark }

        public var scheme: Scheme
        /// The accent color of the Mac as `#RRGGBB`.
        public var accent: String

        public init(scheme: Scheme, accent: String) {
            self.scheme = scheme
            self.accent = accent
        }
    }

    public var plugin: Plugin
    public var items: [Card]
    public var page: Page?
    public var actions: [CardAction]
    public var pending: Pending
    public var status: String?
    public var appearance: Appearance

    enum CodingKeys: String, CodingKey { case plugin, items, page, actions, pending, status, appearance }

    /// The page and the status are null, not absent, so the page can tell them apart from an old host.
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(plugin, forKey: .plugin)
        try values.encode(items, forKey: .items)
        try values.encode(page, forKey: .page)
        try values.encode(actions, forKey: .actions)
        try values.encode(pending, forKey: .pending)
        try values.encode(status, forKey: .status)
        try values.encode(appearance, forKey: .appearance)
    }

    /// `pendingActions` holds `plugin/card` for a card action and `plugin` for a menu action, as `PluginHost` keeps them.
    public static func build(
        plugin entry: PluginEntry, cards: [Card], page: Page?, pendingActions: Set<String>, status: String?, appearance: Appearance
    ) -> PluginUISnapshot {
        let manifest = entry.manifest
        let prefix = "\(entry.id)/"
        return PluginUISnapshot(
            plugin: Plugin(id: entry.id, name: manifest.name, emoji: manifest.emoji, color: manifest.color),
            items: cards.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) },
            page: page,
            actions: manifest.actions,
            pending: Pending(items: pendingActions.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }.sorted(), plugin: pendingActions.contains(entry.id)),
            status: status,
            appearance: appearance)
    }

    /// The JSON that the page gets.
    public var json: String { Reply.json(self) }
}

extension PluginHost {
    /// The snapshot of one plugin, with only its own items.
    public func uiSnapshot(pluginId: String, appearance: PluginUISnapshot.Appearance) -> PluginUISnapshot? {
        guard let entry = plugin(pluginId) else { return nil }
        return PluginUISnapshot.build(
            plugin: entry, cards: board.cards(of: pluginId), page: pages.page(of: pluginId), pendingActions: pendingActions,
            status: pluginActionStatus[pluginId], appearance: appearance)
    }
}
