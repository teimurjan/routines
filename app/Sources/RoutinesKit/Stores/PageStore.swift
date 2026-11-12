import Foundation
import Observation

/// The page of each plugin, one JSON file per plugin. Only the plugin replaces its page.
@MainActor
@Observable
public final class PageStore {
    public private(set) var pages: [String: Page] = [:]
    private let dir: URL
    private let now: () -> Date

    public init(dir: URL, now: @escaping () -> Date = Date.init) {
        self.dir = dir
        self.now = now
    }

    private func file(_ pluginId: String) -> JSONFile<Page?> {
        JSONFile(url: dir.appendingPathComponent("\(pluginId).json"))
    }

    public func load(pluginId: String) {
        if case .success(let loaded) = file(pluginId).load(default: nil) { pages[pluginId] = loaded }
    }

    public func page(of pluginId: String) -> Page? {
        pages[pluginId]
    }

    /// The same blocks keep the file and the time, so a plugin can publish on each run.
    public func publish(_ blocks: [PageBlock], pluginId: String) -> Result<Void, HostError> {
        if pages[pluginId]?.blocks == blocks { return .success(()) }
        let page = Page(blocks: blocks, updatedAt: now())
        let saved = file(pluginId).save(page)
        if case .success = saved { pages[pluginId] = page }
        return saved
    }
}
