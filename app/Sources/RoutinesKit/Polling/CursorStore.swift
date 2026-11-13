import Foundation
import Observation

/// How far each source read, in `sources/<plugin>.json`.
@MainActor
@Observable
public final class CursorStore {
    public struct Cursor: Codable, Equatable, Sendable {
        /// Opaque to the host. Null before the first poll.
        public var cursor: JSONValue = .null
        /// The last good poll.
        public var polledAt: Date?
        /// The last failure. A good poll clears it.
        public var error: String?
    }

    public private(set) var cursors: [String: Cursor] = [:]
    @ObservationIgnored private let dir: URL

    public init(dir: URL) {
        self.dir = dir
    }

    private func file(_ id: String) -> JSONFile<Cursor> {
        JSONFile(url: dir.appendingPathComponent("\(id).json"))
    }

    public func cursor(of id: String) -> Cursor {
        if let cached = cursors[id] { return cached }
        let loaded = (try? file(id).load(default: Cursor()).get()) ?? Cursor()
        cursors[id] = loaded
        return loaded
    }

    /// Only after each item of the poll is stored (FR-021).
    public func moved(_ id: String, to cursor: JSONValue, at date: Date) {
        save(id, Cursor(cursor: cursor, polledAt: date, error: nil))
    }

    /// The cursor stays, so the next poll starts from it.
    public func failed(_ id: String, error: String) {
        var current = cursor(of: id)
        current.error = error
        save(id, current)
    }

    private func save(_ id: String, _ value: Cursor) {
        if case .success = file(id).save(value) { cursors[id] = value }
    }
}
