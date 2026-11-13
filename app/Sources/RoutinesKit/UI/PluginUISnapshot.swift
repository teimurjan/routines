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

    /// An actionable as the page reads it: read-only when the routine owned it before, and the transitions that start from its state.
    public struct Item: Encodable, Equatable, Sendable {
        public var actionable: Actionable
        public var readOnly: Bool
        public var allowed: [String]

        public func encode(to encoder: Encoder) throws {
            try StoredActionable(actionable, readOnly: readOnly, allowed: allowed).encode(to: encoder)
        }
    }

    public var plugin: Plugin
    /// The owned actionables in the card shape, for the UIs of today.
    public var items: [Card]
    public var actionables: [Item]
    public var transitions: [TransitionDeclaration]
    public var page: Page?
    public var actions: [CardAction]
    public var pending: Pending
    public var status: String?
    public var appearance: Appearance

    enum CodingKeys: String, CodingKey { case plugin, items, actionables, transitions, page, actions, pending, status, appearance }

    /// The page and the status are null, not absent, so the page can tell them apart from an old host.
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(plugin, forKey: .plugin)
        try values.encode(items, forKey: .items)
        try values.encode(actionables, forKey: .actionables)
        try values.encode(transitions, forKey: .transitions)
        try values.encode(page, forKey: .page)
        try values.encode(actions, forKey: .actions)
        try values.encode(pending, forKey: .pending)
        try values.encode(status, forKey: .status)
        try values.encode(appearance, forKey: .appearance)
    }

    /// Only the actionables that the routine owns, and those that it owned before (FR-012). A plugin of today names its items by card id.
    /// `pendingActions` holds `plugin/item` for a transition and `plugin` for a plugin action, as `PluginHost` keeps them.
    public static func build(
        plugin entry: PluginEntry, owned: [Actionable], past: [Actionable], page: Page?, pendingActions: Set<String>, status: String?,
        appearance: Appearance
    ) -> PluginUISnapshot {
        let manifest = entry.manifest
        let prefix = "\(entry.id)/"
        let legacy = manifest.role == .legacy
        let shown = legacy ? owned.filter { $0.state != .dropped } : owned
        let allowed = { (actionable: Actionable) in manifest.effectiveTransitions.filter { $0.from.contains(actionable.state) }.map(\.id) }
        return PluginUISnapshot(
            plugin: Plugin(id: entry.id, name: manifest.name, emoji: manifest.emoji, color: manifest.color),
            items: shown.map { $0.card(id: legacy ? $0.dedupeKey : $0.id) }.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) },
            actionables: shown.map { Item(actionable: $0, readOnly: false, allowed: allowed($0)) } + past.map { Item(actionable: $0, readOnly: true, allowed: []) },
            transitions: manifest.transitions,
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
            plugin: entry, owned: actionables.owned(by: pluginId), past: actionables.past(of: pluginId), page: pages.page(of: pluginId),
            pendingActions: pendingActions,
            status: pluginActionStatus[pluginId], appearance: appearance)
    }
}
