import Foundation
import Observation

/// The cards of each plugin, one JSON file per plugin.
@MainActor
@Observable
public final class BoardStore {
    public private(set) var cards: [String: [Card]] = [:]
    /// Cards whose file did not parse. The store does not write over them.
    public private(set) var errors: [String: String] = [:]
    private let dir: URL
    private let now: () -> Date
    /// The days that a plugin keeps its done and failed cards. 0 keeps them. The host sets it from the manifest and your settings.
    public var retentionDays: @MainActor (String) -> Int = { _ in DoneCards.defaultRetentionDays }

    public init(dir: URL, now: @escaping () -> Date = Date.init) {
        self.dir = dir
        self.now = now
    }

    private func file(_ pluginId: String) -> JSONFile<[Card]> {
        JSONFile(url: dir.appendingPathComponent("\(pluginId).json"))
    }

    public func load(pluginId: String) {
        switch file(pluginId).load(default: []) {
        case .success(let loaded):
            cards[pluginId] = Self.pruned(loaded, now: now(), retentionDays: retentionDays(pluginId))
            errors[pluginId] = nil
        case .failure(let error):
            errors[pluginId] = error.description
        }
    }

    public func cards(of pluginId: String) -> [Card] {
        cards[pluginId] ?? []
    }

    public func card(_ pluginId: String, _ cardId: String) -> Card? {
        cards[pluginId]?.first { $0.id == cardId }
    }

    /// The largest `data` of a card, as JSON bytes.
    public static let dataLimit = 32 * 1024

    /// Keeps the place of a card that exists, so the board does not jump.
    public func upsert(_ card: Card, pluginId: String) -> Result<Void, HostError> {
        if let error = errors[pluginId] { return .failure(.failed(error)) }
        if let size = Self.dataSize(card), size > Self.dataLimit {
            return .failure(.failed("the data of card \(card.id) is \(size) bytes as JSON, and the limit is \(Self.dataLimit) bytes (32 KB)"))
        }
        var stored = card
        stored.updatedAt = now()
        var list = cards[pluginId] ?? []
        if let index = list.firstIndex(where: { $0.id == card.id }) {
            list[index] = stored
        } else {
            list.append(stored)
        }
        return commit(list, pluginId: pluginId)
    }

    public func remove(_ cardId: String, pluginId: String) -> Result<Void, HostError> {
        if let error = errors[pluginId] { return .failure(.failed(error)) }
        return commit((cards[pluginId] ?? []).filter { $0.id != cardId }, pluginId: pluginId)
    }

    /// Changes only the status line, for example while an action runs.
    public func setStatus(_ status: String?, cardId: String, pluginId: String) {
        guard var card = card(pluginId, cardId) else { return }
        card.status = status
        _ = upsert(card, pluginId: pluginId)
    }

    /// Deletes the done and failed cards that passed their retention.
    public func prune(pluginId: String) {
        guard errors[pluginId] == nil, let list = cards[pluginId] else { return }
        let kept = Self.pruned(list, now: now(), retentionDays: retentionDays(pluginId))
        if kept.count < list.count { _ = commit(kept, pluginId: pluginId) }
    }

    private func commit(_ list: [Card], pluginId: String) -> Result<Void, HostError> {
        let kept = Self.pruned(list, now: now(), retentionDays: retentionDays(pluginId))
        let saved = file(pluginId).save(kept)
        if case .success = saved { cards[pluginId] = kept }
        return saved
    }

    static func dataSize(_ card: Card) -> Int? {
        guard let data = card.data else { return nil }
        return (try? JSONEncoder().encode(data))?.count
    }

    static func pruned(_ list: [Card], now: Date, retentionDays: Int) -> [Card] {
        guard retentionDays > 0 else { return list }
        let retention = Double(retentionDays) * 24 * 60 * 60
        return list.filter { card in
            guard card.column.isClosed, let updatedAt = card.updatedAt else { return true }
            return now.timeIntervalSince(updatedAt) < retention
        }
    }
}
