import Foundation

/// Moves the cards of `board/<plugin>.json` into actionables once (FR-010). See specs/004-actionables/research.md, section 16.
@MainActor
enum Migration {
    static let trigger = "migration"
    static let suffix = ".migrated"

    /// A file that does not parse stays, so no card is lost. A card that a crash already moved is not moved twice.
    static func run(boardDir: URL, store: ActionableStore) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: boardDir.path)) ?? []
        for name in names.sorted() where name.hasSuffix(".json") {
            let pluginId = String(name.dropLast(5))
            let url = boardDir.appendingPathComponent(name)
            guard case .success(let cards) = JSONFile<[Card]>(url: url).load(default: []) else { continue }
            let moved = cards.allSatisfy { card in move(card, pluginId: pluginId, store: store) }
            guard moved else { continue }
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension(String(suffix.dropFirst())))
        }
    }

    private static func move(_ card: Card, pluginId: String, store: ActionableStore) -> Bool {
        if store.find(source: pluginId, key: card.id) != nil { return true }
        let step = Step.Draft(action: .migrated, actor: "host", trigger: trigger)
        let created = store.create(
            kind: pluginId, source: pluginId, dedupeKey: card.id, owner: pluginId, state: Actionable.State(column: card.column),
            title: BoardAdapter.title(card.title), step: step
        ) { actionable in
            actionable.fill(from: card)
            if let updatedAt = card.updatedAt {
                actionable.createdAt = updatedAt
                actionable.updatedAt = updatedAt
            }
        }
        if case .failure(let error) = created { print("[migration] \(pluginId)/\(card.id): \(error)") }
        return (try? created.get()) != nil
    }
}
