import Foundation
import Observation

public struct Note: Codable, Equatable, Sendable, Identifiable {
    public var number: Int
    public var text: String
    public var at: Date

    public var id: Int { number }
}

/// Your notes per plugin. Only the app writes them, so text from other people cannot teach a routine.
@MainActor
@Observable
public final class NotesStore {
    struct Saved: Codable {
        var next: Int
        var notes: [String: [Note]]
    }

    public private(set) var notes: [String: [Note]] = [:]
    private var next = 1
    private let file: JSONFile<Saved>

    public init(url: URL) {
        file = JSONFile(url: url)
        if case .success(let saved) = file.load(default: Saved(next: 1, notes: [:])) {
            notes = saved.notes
            next = saved.next
        }
    }

    public func notes(of pluginId: String) -> [Note] {
        notes[pluginId] ?? []
    }

    public func add(_ text: String, pluginId: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes[pluginId, default: []].append(Note(number: next, text: trimmed, at: Date()))
        next += 1
        save()
    }

    public func remove(_ number: Int, pluginId: String) {
        notes[pluginId]?.removeAll { $0.number == number }
        save()
    }

    private func save() {
        file.save(Saved(next: next, notes: notes))
    }
}
