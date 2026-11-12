import Foundation
import Observation

public struct HostNotification: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var pluginId: String
    public var title: String
    public var body: String
    public var cardId: String?
    public var at: Date
}

/// The notifications of the last days, which `activity.list` returns. The macOS notification is a separate step, because a test host has no app bundle.
@MainActor
@Observable
public final class NotificationStore {
    public private(set) var items: [HostNotification] = []
    private let file: JSONFile<[HostNotification]>
    static let limit = 300

    public init(url: URL) {
        file = JSONFile(url: url)
        if case .success(let loaded) = file.load(default: []) { items = loaded }
    }

    @discardableResult
    public func add(pluginId: String, title: String, body: String, cardId: String?) -> HostNotification {
        let item = HostNotification(id: UUID(), pluginId: pluginId, title: title, body: body, cardId: cardId, at: Date())
        items = Array(([item] + items).prefix(Self.limit))
        file.save(items)
        return item
    }
}
