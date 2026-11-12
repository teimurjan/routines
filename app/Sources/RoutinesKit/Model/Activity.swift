import Foundation

/// The work of the other plugins since a time. A plugin with `permissions.activity` reads it, for example to write a summary.
public struct Activity: Encodable, Equatable, Sendable {
    public struct Notice: Encodable, Equatable, Sendable {
        public var plugin: String
        public var title: String
        public var body: String
        public var at: Date
    }

    public struct CardChange: Encodable, Equatable, Sendable {
        public var plugin: String
        public var title: String
        public var body: String?
        public var column: Column
        public var status: String?
        public var links: [CardLink]?
        public var at: Date
    }

    public struct FailedRun: Encodable, Equatable, Sendable {
        public var plugin: String
        public var message: String?
        public var at: Date
    }

    public var notifications: [Notice]
    public var cards: [CardChange]
    public var failedRuns: [FailedRun]

    /// A long body, such as a diff, adds cost and no meaning to a summary.
    static let bodyLimit = 600

    /// `names` maps each loaded plugin id to its name. Other plugins and the reader itself stay out. The newest item comes first.
    static func since(
        _ start: Date, reader: String, names: [String: String], cards: [String: [Card]], notifications: [HostNotification], runs: [RunRecord]
    ) -> Activity {
        let name = { (id: String) -> String? in id == reader ? nil : names[id] }
        let changes: [CardChange] = cards.flatMap { id, list -> [CardChange] in
            guard let plugin = name(id) else { return [] }
            return list.compactMap { card -> CardChange? in
                guard let at = card.updatedAt, at >= start else { return nil }
                let body = card.body.map { String($0.prefix(bodyLimit)) }
                return CardChange(plugin: plugin, title: card.title, body: body, column: card.column, status: card.status, links: card.links, at: at)
            }
        }
        let notices: [Notice] = notifications.compactMap { item -> Notice? in
            guard let plugin = name(item.pluginId), item.at >= start else { return nil }
            return Notice(plugin: plugin, title: item.title, body: item.body, at: item.at)
        }
        let failures: [FailedRun] = runs.compactMap { record -> FailedRun? in
            guard let plugin = name(record.pluginId), record.outcome == .failed, record.startedAt >= start else { return nil }
            return FailedRun(plugin: plugin, message: record.message, at: record.startedAt)
        }
        return Activity(
            notifications: notices.sorted { $0.at > $1.at }, cards: changes.sorted { $0.at > $1.at }, failedRuns: failures.sorted { $0.at > $1.at })
    }
}
