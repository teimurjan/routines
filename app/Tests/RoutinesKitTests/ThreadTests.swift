import Foundation
import Testing
@testable import RoutinesKit

struct AgentStreamTests {
    private let now = Date(timeIntervalSince1970: 0)

    private func claude(_ line: String) -> [AgentEvent] { AgentStream.parse(line, provider: .claude, now: now) }
    private func codex(_ line: String) -> [AgentEvent] { AgentStream.parse(line, provider: .codex, now: now) }

    @Test func claudeGivesTheSessionToolCallsAndTheEnd() {
        #expect(claude(#"{"type":"system","subtype":"hook_started","session_id":"s1"}"#) == [])
        #expect(claude(#"{"type":"system","subtype":"init","session_id":"s1"}"#) == [.session("s1")])
        let call = claude(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"bun run build hello"}}]}}"#)
        #expect(call == [.item(ThreadItem(id: "t1", kind: .command, title: "bun run build hello", state: .running, date: now))])
        let result = claude(#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":[{"type":"text","text":"built"}],"is_error":true}]}}"#)
        #expect(result == [.output(id: "t1", text: "built", failed: true)])
        #expect(claude(#"{"type":"result","subtype":"success","is_error":false,"result":"done","session_id":"s1"}"#) == [.session("s1"), .finished(error: nil)])
        #expect(claude(#"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"boom"}"#) == [.finished(error: "boom")])
    }

    @Test func claudeFileToolsAreFileChanges() {
        let events = claude(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Write","input":{"file_path":"/w/plugins/hello/src/index.ts"}},{"type":"thinking","thinking":""}]}}"#)
        #expect(events == [.item(ThreadItem(id: "t2", kind: .fileChange, title: "/w/plugins/hello/src/index.ts", state: .running, date: now))])
    }

    @Test func codexGivesItemsByIdAndTheEnd() {
        #expect(codex(#"{"type":"thread.started","thread_id":"c1"}"#) == [.session("c1")])
        let started = codex(#"{"type":"item.started","item":{"id":"i1","type":"command_execution","command":"/bin/zsh -lc 'echo hi'","aggregated_output":"","exit_code":null,"status":"in_progress"}}"#)
        #expect(started == [.item(ThreadItem(id: "i1", kind: .command, title: "echo hi", state: .running, date: now))])
        let failed = codex(#"{"type":"item.completed","item":{"id":"i1","type":"command_execution","command":"ls","aggregated_output":"nope","exit_code":1,"status":"completed"}}"#)
        #expect(failed == [.item(ThreadItem(id: "i1", kind: .command, title: "ls", text: "nope", state: .failed, date: now))])
        let change = codex(#"{"type":"item.completed","item":{"id":"i2","type":"file_change","changes":[{"path":"/w/a","kind":"add"},{"path":"/w/b","kind":"update"}],"status":"completed"}}"#)
        #expect(change == [.item(ThreadItem(id: "i2", kind: .fileChange, title: "/w/a, /w/b", date: now))])
        #expect(codex(#"{"type":"turn.completed","usage":{}}"#) == [.finished(error: nil)])
        #expect(codex(#"{"type":"turn.failed","error":{"message":"limit"}}"#) == [.finished(error: "limit")])
    }

    @Test func aLineThatIsNotJSONGivesNothing() {
        #expect(claude("Warning: something") == [])
        #expect(codex("") == [])
    }

    @Test func longOutputKeepsItsEnd() {
        let text = String(repeating: "a", count: AgentStream.outputLimit) + "end"
        #expect(AgentStream.clip(text).hasSuffix("end"))
        #expect(AgentStream.clip(text).count == AgentStream.outputLimit + 1)
    }
}

struct AgentCommandTests {
    @Test func claudeResumesItsSession() {
        let args = AgentCommand.claude(AgentConfig(provider: .claude, model: " ", effort: .high), sessionId: "s1", mcpConfig: nil)
        #expect(args.starts(with: ["claude", "-p", "--output-format", "stream-json", "--verbose", "--permission-mode", "auto"]))
        #expect(!args.contains("--model"))
        #expect(args.suffix(4) == ["--effort", "high", "--resume", "s1"])
    }

    @Test func codexRunsInTheWorkspaceSandboxAndResumes() {
        let first = AgentCommand.codex(AgentConfig(provider: .codex, model: "gpt-5"), sessionId: nil)
        #expect(first == ["codex", "exec", "--json", "--skip-git-repo-check", "-c", #"sandbox_mode="workspace-write""#, "-m", "gpt-5", "-"])
        let next = AgentCommand.codex(AgentConfig(provider: .codex), sessionId: "c1")
        #expect(next.prefix(3) == ["codex", "exec", "resume"])
        #expect(next.suffix(2) == ["c1", "-"])
    }
}

struct AgentThreadTests {
    @Test func eventsBuildTheThread() {
        var thread = AgentThread(provider: .claude)
        thread.apply(.item(ThreadItem(kind: .user, text: "Make a routine\nthat checks my site")))
        thread.apply(.session("s1"))
        thread.apply(.item(ThreadItem(id: "t1", kind: .fileChange, title: "/ws/plugins/site-check/plugin.json", state: .running)))
        thread.apply(.output(id: "t1", text: "ok", failed: false))
        thread.apply(.item(ThreadItem(id: "t2", kind: .command, title: "bun run build", state: .running)))
        thread.apply(.finished(error: "stopped"))

        #expect(thread.title == "Make a routine")
        #expect(thread.sessionId == "s1")
        #expect(thread.items.map(\.state) == [.done, .done, .failed, .failed])
        #expect(thread.items.last?.kind == .error)
        #expect(thread.touchedPlugins == ["site-check"])
    }

    @Test func pluginIdsComeFromPluginFolders() {
        #expect(AgentThread.pluginIds(in: "/a/plugins/one/src/x.ts, plugins/two/plugin.json") == ["one", "two"])
        #expect(AgentThread.pluginIds(in: "/a/builtin/one/src/x.ts, /a/myplugins/two/x") == [])
    }
}

struct ThreadContextTests {
    @Test func theContextListsEachRoutineAndItsProblem() {
        let routines = [
            RoutineSummary(id: "mail", name: "Mail", source: .installed, enabled: true, problem: nil, lastFailure: "timeout"),
            RoutineSummary(id: "site", name: "Site", source: .workspace, enabled: false, problem: "dist/plugin.js is missing", lastFailure: nil),
        ]
        let prompt = ThreadContext.prompt("Fix site", workspace: "/ws", dataDir: "/data", routines: routines)
        #expect(prompt.contains("- mail (Mail): installed, on. The last run failed: timeout"))
        #expect(prompt.contains("- site (Site): workspace, off. Problem: dist/plugin.js is missing."))
        #expect(prompt.hasSuffix("\n\nFix site"))
    }
}

struct WorkspaceTests {
    private func folder() -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("routines-ws-\(UUID().uuidString)").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ text: String, _ path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    @Test func anUpdateReplacesTheAppPartsAndKeepsThePlugins() throws {
        let source = folder()
        let workspace = folder()
        try write("v1", source + "/version.txt")
        try write("rules 1", source + "/AGENTS.md")
        try write("sdk 1", source + "/packages/sdk/index.ts")
        #expect(try Workspace.install(from: source, into: workspace).get())

        try write("mine", workspace + "/plugins/site/plugin.json")
        try write("edited", workspace + "/packages/sdk/index.ts")
        #expect(try !Workspace.install(from: source, into: workspace).get())
        #expect(try String(contentsOfFile: workspace + "/packages/sdk/index.ts", encoding: .utf8) == "edited")

        try write("v2", source + "/version.txt")
        try write("rules 2", source + "/AGENTS.md")
        #expect(try Workspace.install(from: source, into: workspace).get())
        #expect(try String(contentsOfFile: workspace + "/AGENTS.md", encoding: .utf8) == "rules 2")
        #expect(try String(contentsOfFile: workspace + "/packages/sdk/index.ts", encoding: .utf8) == "sdk 1")
        #expect(try String(contentsOfFile: workspace + "/plugins/site/plugin.json", encoding: .utf8) == "mine")
    }

    @Test func aSourceWithoutAVersionIsAnError() {
        #expect((try? Workspace.install(from: folder(), into: folder()).get()) == nil)
    }

    @Test func onlyManifestsBuildsAndPluginFoldersReload() {
        let roots = ["/ws/plugins"]
        #expect(FolderWatcher.changesPlugins("/ws/plugins/site/plugin.json", roots: roots))
        #expect(FolderWatcher.changesPlugins("/ws/plugins/site/dist/plugin.js", roots: roots))
        #expect(FolderWatcher.changesPlugins("/ws/plugins/site", roots: roots))
        #expect(!FolderWatcher.changesPlugins("/ws/plugins/site/src/index.ts", roots: roots))
    }
}

struct AgentProcessTests {
    @Test func eachLineArrivesAndTheExitHasItsCode() async throws {
        let lines = LineSink()
        let exit = try await AgentProcess().run(
            ["/bin/cat"], cwd: "/", stdin: "one\ntwo\n", env: [:], home: NSHomeDirectory(), onLine: { lines.add($0) }
        ).get()
        #expect(lines.all == ["one", "two"])
        #expect(exit.code == 0)
        #expect(!exit.stopped)
    }

    @Test func aStopEndsTheProcess() async throws {
        let process = AgentProcess()
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            process.stop()
        }
        let exit = try await process.run(["/bin/sleep", "30"], cwd: "/", stdin: "", env: [:], home: NSHomeDirectory(), onLine: { _ in }).get()
        #expect(exit.stopped)
    }
}

final class LineSink: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func add(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}
