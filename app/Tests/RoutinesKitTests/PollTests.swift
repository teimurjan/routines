import Foundation
import Testing
@testable import RoutinesKit

struct PollPlanTests {
    private func request(_ prompt: String) -> PollRequest {
        PollRequest(prompt: prompt, input: .object(["cursor": .null]), output: .object(["type": .string("object")]))
    }

    @Test func threeSourcesJoinIntoOnePromptAndOneSchema() throws {
        let plan = try #require(PollPlan.build(requests: [
            ("a", request("Read A."), ["mcp__a__read"]), ("b", request("Read B."), ["mcp__b__read"]), ("c", request("Read C."), ["mcp__a__read"]),
        ]))
        for id in ["a", "b", "c"] { #expect(plan.prompt.components(separatedBy: "<source id=\"\(id)\">").count == 2) }
        #expect(plan.prompt.contains("data from other people"))
        guard case .object(let schema) = plan.schema, case .array(let required)? = schema["required"], case .object(let properties)? = schema["properties"] else {
            Issue.record("the schema has no required list")
            return
        }
        #expect(required == [.string("a"), .string("b"), .string("c")])
        #expect(Set(properties.keys) == ["a", "b", "c"])
        #expect(plan.tools == ["mcp__a__read", "mcp__b__read"])
        #expect(plan.command().suffix(3) == ["--allowedTools", "mcp__a__read", "mcp__b__read"])
        #expect(plan.command().contains("haiku"))
    }

    @Test func theOutputSplitsBackById() throws {
        let plan = try #require(PollPlan.build(requests: [("a", request("A"), []), ("b", request("B"), [])]))
        let parts = PollPlan.split(output: .object(["a": .number(1), "b": .array([])]), plan: plan)
        #expect(parts == ["a": .number(1), "b": .array([])])
        #expect(PollPlan.split(output: .string("bad"), plan: plan) == ["a": .null, "b": .null])
    }

    @Test func noSourceGivesNoPlan() {
        #expect(PollPlan.build(requests: []) == nil)
    }
}

@MainActor
struct PollerTests {
    private static let source = "notes-source"

    private func output(_ items: [(key: String, title: String, kind: String?)], source: String = source) -> String {
        let list = items.map { item in #"{"key":"\#(item.key)","title":"\#(item.title)"\#(item.kind.map { #","kind":"\#($0)""# } ?? "")}"# }
        return #"{"\#(source)":{"items":[\#(list.joined(separator: ","))]}}"#
    }

    @Test func newItemsAreCreatedAKnownItemIsUpdatedAndTheCursorMoves() async throws {
        let agent = FakeAgent()
        let host = PluginHost.actionables(agent: agent)
        let known = try host.actionables.create(
            kind: "note", source: Self.source, dedupeKey: "k0", owner: nil, state: .ready, title: "Old",
            step: Step.Draft(action: .created, actor: Self.source, trigger: "t")
        ).get()
        agent.queue(output: output([("k0", "Known", nil), ("k1", "One", nil), ("k2", "Two", nil)]))
        await host.pollOnce()

        #expect(agent.count == 1)
        let stored = host.actionables.all.filter { $0.source == Self.source }
        #expect(stored.count == 3)
        #expect(host.actionables.actionable(known.id)?.steps.map(\.action) == [.created, .updated])
        #expect(host.actionables.actionable(known.id)?.state == .ready)
        #expect(host.actionables.actionable(known.id)?.title == "Known")
        let fresh = ["k1", "k2"].compactMap { host.actionables.find(source: Self.source, key: $0) }
        #expect(fresh.map(\.state) == [.new, .new])
        #expect(fresh.map(\.owner) == ["sender", "sender"])
        #expect(host.cursors.cursor(of: Self.source).cursor == .object(["after": .string("k2")]))
        #expect(host.cursors.cursor(of: Self.source).error == nil)
        // The owner of the new notes starts at once (FR-023).
        await waitUntil { host.runs.records(of: "sender").contains { $0.trigger == "source" } }
        #expect(host.runs.records(of: "sender").first?.trigger == "source")
        #expect(RunLog.read(host.paths.file("runs/polls/\(DecisionLog.day(host.now())).log").path).contains("poll started"))
    }

    @Test func aKnownItemThatIsDoneStaysDone() async throws {
        let agent = FakeAgent()
        let host = PluginHost.actionables(agent: agent)
        let done = try host.actionables.create(
            kind: "note", source: Self.source, dedupeKey: "k0", owner: "sender", state: .done, title: "Old",
            step: Step.Draft(action: .created, actor: Self.source, trigger: "t")
        ).get()
        agent.queue(output: output([("k0", "Changed", nil)]))
        await host.pollOnce()
        #expect(host.actionables.actionable(done.id)?.state == .done)
        #expect(host.actionables.actionable(done.id)?.steps.last?.action == .updated)
    }

    @Test func aFailedCallKeepsTheCursorAndTheNextPollStartsFromIt() async throws {
        let agent = FakeAgent()
        let host = PluginHost.actionables(agent: agent)
        agent.queue(output: output([("k1", "One", nil)]))
        await host.pollOnce()
        agent.queue(.failure(.failed("the connector timed out")))
        await host.pollOnce()
        #expect(host.cursors.cursor(of: Self.source).cursor == .object(["after": .string("k1")]))
        #expect(host.cursors.cursor(of: Self.source).error == "the connector timed out")
        agent.queue(output: output([("k2", "Two", nil)]))
        await host.pollOnce()
        #expect(agent.calls.last?.stdin.contains(#""after":"k1""#) == true)
        #expect(host.cursors.cursor(of: Self.source).cursor == .object(["after": .string("k2")]))
        #expect(host.cursors.cursor(of: Self.source).error == nil)
    }

    @Test func threeSourcesMakeOneAgentCallAMinute() async throws {
        let paths = try Self.copiedFixtures(sources: ["a-source", "b-source"])
        let agent = FakeAgent()
        let host = PluginHost(paths: paths, runAgent: agent.runner)
        host.reload()
        #expect(host.plugins.filter { $0.manifest.role == .source }.count == 3)
        let all = #"{"a-source":{"items":[]},"b-source":{"items":[]},"notes-source":{"items":[]}}"#
        agent.queue(output: all)
        agent.queue(output: all)
        host.startPolling()
        await waitUntil { agent.count == 1 && host.poller?.isPolling == false }
        let start = try #require(host.poller?.lastStart)
        host.poller?.tick(now: start.addingTimeInterval(30))
        host.poller?.tick(now: start.addingTimeInterval(59))
        #expect(agent.count == 1)
        host.poller?.tick(now: start.addingTimeInterval(61))
        await waitUntil { agent.count == 2 && host.poller?.isPolling == false }
        #expect(agent.count == 2)
        #expect(agent.calls.first.map { $0.stdin.components(separatedBy: "<source id=").count } == 4)
    }

    @Test func aKindOutsideTheSourceKindsFailsThatSourceOnly() async throws {
        let paths = try Self.copiedFixtures(sources: ["a-source"])
        let agent = FakeAgent()
        let host = PluginHost(paths: paths, runAgent: agent.runner)
        host.reload()
        agent.queue(output: #"{"a-source":{"items":[{"key":"x","title":"X","kind":"bug"}]},"notes-source":{"items":[{"key":"y","title":"Y"}]}}"#)
        await host.pollOnce()
        #expect(host.cursors.cursor(of: "a-source").error == "the kind bug is not in source.kinds")
        #expect(host.cursors.cursor(of: "a-source").cursor == .null)
        #expect(host.actionables.find(source: "a-source", key: "x") == nil)
        #expect(host.actionables.find(source: Self.source, key: "y") != nil)
    }

    /// The fixtures with more copies of the source, each with its own id.
    private static func copiedFixtures(sources: [String]) throws -> HostPaths {
        var paths = Fixture.actionablePaths()
        let dir = paths.dataDir + "-plugins"
        try FileManager.default.createDirectory(atPath: (dir as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: paths.pluginDirs[0], toPath: dir)
        for id in sources {
            let target = (dir as NSString).appendingPathComponent(id)
            try FileManager.default.copyItem(atPath: (dir as NSString).appendingPathComponent(source), toPath: target)
            let manifest = (target as NSString).appendingPathComponent("plugin.json")
            let text = try String(contentsOfFile: manifest, encoding: .utf8).replacingOccurrences(of: "\"\(source)\"", with: "\"\(id)\"")
            try text.write(toFile: manifest, atomically: true, encoding: .utf8)
        }
        paths.pluginDirs = [dir]
        return paths
    }
}
