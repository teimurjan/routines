import Foundation
import Observation

/// The memory entries in `memory/entries.json`, and the steps that wait for the memory node in `memory/pending.json`.
@MainActor
@Observable
public final class MemoryStore {
    public struct Pending: Codable, Equatable, Sendable {
        public var step: String
        /// The run log that names a failure of the memory node.
        public var log: String?
        public var failures: Int = 0
    }

    public private(set) var entries: [MemoryEntry] = []
    public private(set) var pending: [Pending] = []
    @ObservationIgnored private let entriesFile: JSONFile<[MemoryEntry]>
    @ObservationIgnored private let pendingFile: JSONFile<[Pending]>
    @ObservationIgnored private let now: @Sendable () -> Date
    static let maxFailures = 3

    public init(dir: URL, now: @escaping @Sendable () -> Date = Date.init) {
        entriesFile = JSONFile(url: dir.appendingPathComponent("entries.json"))
        pendingFile = JSONFile(url: dir.appendingPathComponent("pending.json"))
        self.now = now
        entries = (try? entriesFile.load(default: []).get()) ?? []
        pending = (try? pendingFile.load(default: []).get()) ?? []
    }

    public var entriesURL: URL { entriesFile.url }

    public func enqueue(steps: [String], log: String?) {
        let known = Set(pending.map(\.step))
        let added = steps.filter { !known.contains($0) }.map { Pending(step: $0, log: log) }
        guard !added.isEmpty else { return }
        pending += added
        pendingFile.save(pending)
    }

    public func take(_ count: Int) -> [Pending] {
        Array(pending.prefix(count))
    }

    /// Writes the entries, then removes their steps from the queue.
    public func write(entries new: [MemoryEntry], done steps: [String]) {
        if !new.isEmpty {
            guard case .success = entriesFile.save(entries + new) else { return }
            entries += new
        }
        pending.removeAll { steps.contains($0.step) }
        pendingFile.save(pending)
    }

    /// A step that fails three times leaves the queue. Returns the steps that left.
    @discardableResult
    public func failed(_ steps: [String]) -> [String] {
        pending = pending.map { item in steps.contains(item.step) ? Pending(step: item.step, log: item.log, failures: item.failures + 1) : item }
        let dropped = pending.filter { $0.failures >= Self.maxFailures }.map(\.step)
        pending.removeAll { $0.failures >= Self.maxFailures }
        pendingFile.save(pending)
        return dropped
    }

    public func edit(id: String, text: String, tags: [String]) -> Result<Void, HostError> {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return .failure(.failed("there is no entry \(id)")) }
        return MemoryEntry.check(text: text, tags: tags).flatMap { text, tags in
            var changed = entries
            changed[index].text = text
            changed[index].tags = tags
            changed[index].editedAt = now()
            return entriesFile.save(changed).map { entries = changed }
        }
    }

    public func delete(id: String) {
        let kept = entries.filter { $0.id != id }
        if case .success = entriesFile.save(kept) { entries = kept }
    }
}
