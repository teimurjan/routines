import Foundation
import Observation

/// Runs the turns of the threads with the coding agent in the workspace. Each thread runs one turn at a time, and threads run side by side.
@MainActor
@Observable
public final class ThreadService {
    public let store: ThreadStore
    public private(set) var status: AgentStatus?
    private var turns: [String: AgentProcess] = [:]
    private let host: PluginHost

    public init(host: PluginHost) {
        self.host = host
        store = ThreadStore(dir: host.paths.file("threads"))
    }

    public var config: AgentConfig {
        get { host.settings.agent }
        set {
            let providerChanged = newValue.provider != host.settings.agent.provider
            host.settings.agent = newValue
            if providerChanged { Task { await checkAgent() } }
        }
    }

    public var runningCount: Int { turns.count }

    public func isRunning(_ threadId: String) -> Bool {
        turns[threadId] != nil
    }

    public func checkAgent() async {
        let provider = config.provider
        let checked = await AgentHealth.check(provider, home: host.paths.home)
        if provider == config.provider { status = checked }
    }

    public func newThread() -> AgentThread {
        store.create(provider: config.provider)
    }

    public func send(_ message: String, threadId: String) {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning(threadId), let thread = store.thread(threadId) else { return }
        store.update(threadId) { $0.items.append(ThreadItem(kind: .user, text: text)) }

        let paths = host.paths
        let prompt = ThreadContext.prompt(text, workspace: paths.workspaceDir, dataDir: paths.dataDir, routines: host.routineSummaries())
        let command = command(for: thread)
        let provider = thread.provider
        let process = AgentProcess()
        turns[threadId] = process
        let (stream, lines) = AsyncStream<[AgentEvent]>.makeStream()
        let turn = Task.detached {
            let exit = await process.run(
                command, cwd: paths.workspaceDir, stdin: prompt, env: AgentEnvironment.full(provider, home: paths.home), home: paths.home
            ) { line in
                let events = AgentStream.parse(line, provider: provider)
                if !events.isEmpty { lines.yield(events) }
            }
            lines.finish()
            return exit
        }
        // One consumer applies the events in order, so the end of the turn comes after its last line.
        Task { @MainActor in
            var ended = false
            for await events in stream {
                store.update(threadId) { thread in events.forEach { thread.apply($0) } }
                ended = ended || events.contains { if case .finished = $0 { true } else { false } }
            }
            finish(threadId, exit: await turn.value, ended: ended)
        }
    }

    public func stop(_ threadId: String) {
        turns[threadId]?.stop()
    }

    public func delete(_ threadId: String) {
        stop(threadId)
        store.delete(threadId)
    }

    private func command(for thread: AgentThread) -> [String] {
        var settings = config
        settings.provider = thread.provider
        switch thread.provider {
        case .claude:
            let mcpConfig = (host.paths.home as NSString).appendingPathComponent(".mcp.json")
            return AgentCommand.claude(settings, sessionId: thread.sessionId, mcpConfig: FileManager.default.fileExists(atPath: mcpConfig) ? mcpConfig : nil)
        case .codex:
            return AgentCommand.codex(settings, sessionId: thread.sessionId)
        }
    }

    /// A turn that ended without its result event gets an error item, so the thread never looks busy.
    private func finish(_ threadId: String, exit: Result<AgentProcess.Exit, HostError>, ended: Bool) {
        turns[threadId] = nil
        guard !ended else { return }
        let reason: String = switch exit {
        case .failure(let error): error.description
        case .success(let exit) where exit.stopped: "You stopped the turn."
        case .success(let exit): exit.stderr.isEmpty ? "The agent ended with exit code \(exit.code)." : exit.stderr
        }
        store.update(threadId) { $0.apply(.finished(error: reason)) }
    }
}
