import Foundation
import Observation

/// The threads, one JSON file each in `threads/`, newest first.
@MainActor
@Observable
public final class ThreadStore {
    public private(set) var threads: [AgentThread] = []
    /// The files that did not parse. The store leaves them on disk.
    public private(set) var errors: [String] = []
    private let dir: URL

    public init(dir: URL) {
        self.dir = dir
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names where name.hasSuffix(".json") {
            switch JSONFile<AgentThread>(url: dir.appendingPathComponent(name)).load(default: AgentThread(provider: .claude)) {
            case .success(let thread): threads.append(thread)
            case .failure(let error): errors.append(error.description)
            }
        }
        sort()
    }

    public func thread(_ id: String) -> AgentThread? {
        threads.first { $0.id == id }
    }

    public func create(provider: AgentProvider) -> AgentThread {
        let thread = AgentThread(provider: provider)
        threads.insert(thread, at: 0)
        return thread
    }

    /// Changes a thread and saves it. A thread without items stays in memory only.
    public func update(_ id: String, _ change: (inout AgentThread) -> Void) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        change(&threads[index])
        let thread = threads[index]
        if !thread.items.isEmpty { file(id).save(thread) }
        sort()
    }

    public func delete(_ id: String) {
        threads.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: file(id).url)
    }

    private func file(_ id: String) -> JSONFile<AgentThread> {
        JSONFile(url: dir.appendingPathComponent("\(id).json"))
    }

    private func sort() {
        threads.sort { $0.updatedAt > $1.updatedAt }
    }
}
