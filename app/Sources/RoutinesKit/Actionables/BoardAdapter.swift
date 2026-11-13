import Foundation

/// The board calls of the plugins of today. Each card is an actionable with the plugin as source, owner and kind, and the card id as dedupe key.
@MainActor
public struct BoardAdapter {
    let store: ActionableStore

    public init(store: ActionableStore) {
        self.store = store
    }

    /// The cards of a plugin in the order that it made them. A removed card is gone from the board.
    public func cards(of pluginId: String) -> [Card] {
        store.owned(by: pluginId).filter { $0.source == pluginId && $0.state != .dropped }
            .sorted { (Int($0.id) ?? 0) < (Int($1.id) ?? 0) }
            .map { $0.card(id: $0.dedupeKey) }
    }

    public func card(_ pluginId: String, _ cardId: String) -> Card? {
        guard let actionable = store.find(source: pluginId, key: cardId), actionable.state != .dropped else { return nil }
        return actionable.card(id: cardId)
    }

    /// A new column adds a `board` step. The state keeps its finer value while the column stays, for example `new` in Planned.
    @discardableResult
    public func upsert(_ card: Card, pluginId: String, trigger: String) -> Result<Void, HostError> {
        guard let existing = store.find(source: pluginId, key: card.id) else {
            let step = Step.Draft(action: .created, actor: pluginId, trigger: trigger)
            return store.create(
                kind: pluginId, source: pluginId, dedupeKey: card.id, owner: pluginId, state: Actionable.State(column: card.column),
                title: Self.title(card.title), step: step
            ) { $0.fill(from: card) }.map { _ in () }
        }
        let state = existing.state.column == card.column && existing.state != .dropped ? existing.state : Actionable.State(column: card.column)
        let step = state == existing.state ? nil : Step.Draft(action: .board, actor: pluginId, trigger: trigger)
        return store.update(existing.id, step: step) { actionable in
            actionable.fill(from: card)
            actionable.state = state
        }.map { _ in () }
    }

    public func remove(_ cardId: String, pluginId: String, trigger: String) -> Result<Void, HostError> {
        guard let existing = store.find(source: pluginId, key: cardId), existing.state != .dropped else { return .success(()) }
        return store.update(existing.id, step: Step.Draft(action: .board, actor: pluginId, trigger: trigger)) { $0.state = .dropped }.map { _ in () }
    }

    public func setStatus(_ status: String?, cardId: String, pluginId: String) {
        guard let existing = store.find(source: pluginId, key: cardId) else { return }
        store.setStatus(status, of: existing.id)
    }

    nonisolated static func title(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(ActionableStore.titleLimit))
    }
}

extension Actionable {
    /// The display fields of a card. Links that are not `http` or `https` never opened, so they go.
    mutating func fill(from card: Card) {
        title = BoardAdapter.title(card.title)
        body = card.body
        progress = card.progress
        date = card.date
        tags = card.tags
        links = (card.links ?? []).filter { link in ["http", "https"].contains(URL(string: link.url)?.scheme?.lowercased() ?? "") }
        images = card.images
        status = card.status
        data = card.data ?? .object([:])
    }
}
