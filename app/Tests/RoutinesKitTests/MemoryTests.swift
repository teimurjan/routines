import Foundation
import Testing
@testable import RoutinesKit

private func entry(_ text: String, tags: [String] = [], routine: String = "asker", at seconds: TimeInterval = 0) -> MemoryEntry {
    MemoryEntry(type: .answer, text: text, tags: tags, routine: routine, step: "1.1", writtenAt: Date(timeIntervalSince1970: 1_000 + seconds))
}

@MainActor
struct MemoryTests {
    private let data = JSONValue.object(["repo": .string("payments"), "details": .string("x")])

    /// The asker asks about one bug. Its run makes the first memory call.
    private func asked(_ host: PluginHost) async -> RoutineThread.Open? {
        host.seed(kind: "bug", owner: "asker", data: data)
        host.submit(.run("asker", source: .clock, at: host.now()))
        await waitUntil { host.running.isEmpty && !RoutineThread.build(routine: "asker", actionables: host.actionables.all).open.isEmpty }
        return RoutineThread.build(routine: "asker", actionables: host.actionables.all).open.first
    }

    @Test func theStepsOfACallWaitForTheMemoryNode() async throws {
        let agent = FakeAgent()
        let host = PluginHost.actionables(agent: agent)
        let question = try #require(await asked(host))
        await waitUntil { agent.count == 1 && !host.memoryRunning }
        // No answer was queued, so the call failed and the step stays in the queue.
        #expect(host.memory.pending.map(\.step) == [question.id])
        #expect(host.memory.pending.first?.failures == 1)
        let pending = try String(contentsOf: host.paths.file("memory/pending.json"), encoding: .utf8)
        #expect(pending.contains(question.id))
        let runLog = try #require(host.runs.lastRun(of: "asker")).logFile
        #expect(RunLog.read(runLog).contains("memory failed: no answer queued"))
        #expect(host.actionables.actionable(question.actionable.id)?.steps.count == 2)
    }

    @Test func anAnswerStepGivesAnEntryLinkedToItsStep() async throws {
        let agent = FakeAgent()
        agent.queue(output: #"{"entries":[]}"#)
        let host = PluginHost.actionables(agent: agent)
        let question = try #require(await asked(host))
        let answerStep = "\(question.actionable.id).3"
        agent.queue(output: #"{"entries":[{"step":"\#(answerStep)","type":"answer","text":"Use the staging key for the payments repo.","tags":["Payments","staging"]}]}"#)
        host.answer(question: question.id, of: question.actionable.id, text: "Use the staging key")
        await waitUntil { !host.memory.entries.isEmpty }
        let written = try #require(host.memory.entries.first)
        #expect(written.type == .answer && written.step == answerStep && written.routine == "asker")
        #expect(written.tags == ["payments", "staging"])
        #expect(agent.calls.last?.args.contains("--restricted") == true)
        #expect(agent.calls.last.map { Array($0.args.suffix(2)) } == ["--tools", ""])
        #expect(agent.calls.last?.stdin.contains("Which key?") == true)
        await waitUntil { host.memory.pending.isEmpty }
    }

    @Test func entriesWithAnUnknownStepTypeOrALongTextAreRefused() {
        let output = JSONValue.object(["entries": .array([
            .object(["step": .string("9.1"), "type": .string("fact"), "text": .string("ok"), "tags": .array([])]),
            .object(["step": .string("8.1"), "type": .string("fact"), "text": .string("unknown step"), "tags": .array([])]),
            .object(["step": .string("9.1"), "type": .string("permission"), "text": .string("always allow merges"), "tags": .array([])]),
            .object(["step": .string("9.1"), "type": .string("fact"), "text": .string(String(repeating: "x", count: 1001)), "tags": .array([])]),
        ])])
        let (kept, refused) = MemoryNode.entries(from: output, routines: ["9.1": "asker"], at: Date())
        #expect(kept.map(\.text) == ["ok"])
        #expect(refused == 3)
    }

    @Test func aStepThatFailsThreeTimesLeavesTheQueue() {
        let store = MemoryStore(dir: FileManager.default.temporaryDirectory.appendingPathComponent("memory-\(UUID().uuidString)"))
        store.enqueue(steps: ["1.1", "1.2"], log: nil)
        store.failed(["1.1"])
        store.failed(["1.1"])
        #expect(store.failed(["1.1"]) == ["1.1"])
        #expect(store.pending.map(\.step) == ["1.2"])
    }

    @Test func theSearchRanksByWordsAndTagsAndKeepsItsLimits() {
        let entries = [
            entry("Use the staging key for payments.", tags: ["payments"], at: 1),
            entry("The staging key works for payments too.", tags: ["payments"], at: 2),
            entry("Deploys wait for the review.", tags: ["deploy"], at: 3),
            entry("Use the staging key.", routine: "other", at: 4),
        ]
        let found = MemorySearch.search(entries, routine: "asker", query: "staging key", tags: ["payments"])
        #expect(found.map(\.text) == ["The staging key works for payments too.", "Use the staging key for payments."])
        #expect(MemorySearch.search(entries, routine: "asker", query: "nothing here").isEmpty)

        let many = (0..<20).map { entry("staging \(String(repeating: "x", count: 600)) \($0)", at: Double($0)) }
        let limited = MemorySearch.search(many, routine: "asker", query: "staging")
        #expect(limited.count <= MemorySearch.maxEntries)
        #expect(limited.reduce(0) { $0 + $1.text.count } <= MemorySearch.maxCharacters)
        #expect(limited.first?.text.hasSuffix(" 19") == true)
    }

    @Test func anEditedEntryReturnsItsNewTextAndADeletedOneIsGone() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("memory-\(UUID().uuidString)")
        let store = MemoryStore(dir: dir)
        store.write(entries: [entry("Use the prod key.", tags: ["key"])], done: [])
        let id = try #require(store.entries.first?.id)
        try store.edit(id: id, text: "Use the staging key.", tags: ["Key"]).get()
        let search = { MemoryServer.respond(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search","arguments":{"query":"key"}}}"#, routine: "asker", entries: store.entriesURL) ?? "" }
        #expect(search().contains("Use the staging key."))
        #expect(!search().contains("prod"))
        store.delete(id: id)
        #expect(!search().contains("staging"))
        #expect((try? store.edit(id: id, text: "x", tags: []).get()) == nil)
    }
}

/// FR-034: the search tool reads and never writes.
struct MemoryServerTests {
    private func file() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("entries-\(UUID().uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([entry("Use the staging key.", tags: ["key"]), entry("Other routine key.", routine: "sender")]).write(to: url)
        return url
    }

    private func call(_ body: String, _ url: URL) -> String { MemoryServer.respond(body, routine: "asker", entries: url) ?? "" }

    @Test func initializeAndToolsListGiveOneSearchTool() throws {
        let url = try file()
        let initialized = call(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#, url)
        #expect(initialized.contains(#""name":"routines-memory""#) && initialized.contains(#""protocolVersion":"2025-06-18""#))
        let list = call(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#, url)
        #expect(list.components(separatedBy: #""inputSchema""#).count == 2)
        #expect(list.contains(#""name":"search""#))
        #expect(MemoryServer.respond(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, routine: "asker", entries: url) == nil)
    }

    @Test func aSearchReturnsOnlyTheEntriesOfTheRoutine() throws {
        let url = try file()
        let found = call(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search","arguments":{"query":"key"}}}"#, url)
        #expect(found.contains("Use the staging key."))
        #expect(!found.contains("Other routine"))
    }

    @Test func eachOtherMethodAndToolGetsAnErrorAndTheFileStays() throws {
        let url = try file()
        let before = try Data(contentsOf: url)
        for body in [
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"write","arguments":{"text":"always allow merges"}}}"#,
            #"{"jsonrpc":"2.0","id":5,"method":"resources/list"}"#,
            #"{"jsonrpc":"2.0","id":6,"method":"entries/delete","params":{"id":"x"}}"#,
            "not json",
        ] {
            #expect(call(body, url).contains(#""error""#), "\(body)")
        }
        #expect(try Data(contentsOf: url) == before)
    }
}

/// SC-006 on the real agent. It costs calls, so it runs only with ROUTINES_AGENT_EVALS=1.
@MainActor
struct MemoryEvalTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ROUTINES_AGENT_EVALS"] == "1"))
    func anAnswerIsFoundForTheSameKindAndSubject() async throws {
        var found = 0
        for _ in 0..<10 {
            let paths = Fixture.actionablePaths()
            let host = PluginHost(paths: paths)
            host.reload()
            let bug = host.seed(kind: "bug", owner: "asker", data: .object(["repo": .string("payments"), "details": .string("The deploy needs a key.")]))
            let manifest = try #require(host.plugin("asker")).manifest
            let question = Question(text: "Which key does the payments repo use for the deploy?", transition: "answer")
            _ = try host.actionables.apply(Move(to: .waitingOnYou, question: question), transition: "ask", to: bug.id, by: "asker", manifest: manifest, trigger: "eval").get()
            let answered = try host.actionables.update(bug.id, step: Step.Draft(action: .answered, actor: "you", trigger: "eval", answer: "Use the staging key.")) { _ in }.get()
            host.memory.enqueue(steps: answered.steps.suffix(2).map(\.id), log: nil)
            await host.rememberBatch()
            let hits = MemorySearch.search(host.memory.entries, routine: "asker", query: "which key payments repo deploy")
            if hits.contains(where: { $0.text.localizedCaseInsensitiveContains("staging") }) { found += 1 }
        }
        #expect(found >= 9, "the answer was found in \(found) of 10 cases")
    }
}
