import Foundation
import Testing
@testable import RoutinesKit

@MainActor
struct HostTests {
    private func loadedHost() -> PluginHost {
        let host = PluginHost(paths: Fixture.paths())
        host.reload()
        return host
    }

    @Test func aRunUsesTheHostAPIsAndTheWebPolyfills() async throws {
        let host = loadedHost()
        host.runNow("echo")
        await waitUntil { host.running.isEmpty && host.runs.lastRun(of: "echo")?.outcome != .running }

        let record = try #require(host.runs.lastRun(of: "echo"))
        #expect(record.outcome == .succeeded)
        #expect(record.message == "hi")
        let written = try String(contentsOfFile: host.paths.stateDir + "/echo.txt", encoding: .utf8)
        #expect(written == "manual:hey:1:2:aGk=")
        #expect(host.notifications.items.first?.cardId == "c1")
        #expect(host.pages.page(of: "echo")?.blocks == [.status(PageStatus(state: .ok, label: "Up")), .markdown("Hello")])
        #expect(RunLog.read(record.logFile).contains("logged {\"a\":1}"))
    }

    @Test func theManifestLimitsCommandsAndPaths() async throws {
        let host = loadedHost()
        host.runNow("echo")
        await waitUntil { host.board.card("echo", "c1") != nil && host.running.isEmpty }

        let status = try #require(host.board.card("echo", "c1")?.status)
        #expect(status.contains("the command rm is not in permissions.exec"))
        #expect(status.contains("the path /etc/hosts is not in permissions.paths"))
    }

    @Test func anActionMovesItsCardAndSetsTheStatus() async throws {
        let host = loadedHost()
        host.runNow("echo")
        await waitUntil { host.board.card("echo", "c1") != nil && host.running.isEmpty }

        host.perform("done", cardId: "c1", pluginId: "echo", text: "now")
        await waitUntil { host.pendingActions.isEmpty }
        let card = try #require(host.board.card("echo", "c1"))
        #expect(card.column == .done)
        #expect(card.status == "moved now")
    }

    @Test func aMenuActionCallsOnPluginActionAndShowsItsAnswer() async throws {
        let host = loadedHost()
        host.performPluginAction("watch", pluginId: "echo", text: "a car")
        await waitUntil { host.pendingActions.isEmpty }
        #expect(host.pluginActionStatus["echo"] == "watch a car")
        #expect(host.runs.records.first?.trigger == "watch")
    }

    @Test func aCardFromTheListCanBeSavedAgain() async throws {
        let host = loadedHost()
        host.runNow("echo")
        await waitUntil { host.board.card("echo", "c1") != nil && host.running.isEmpty }
        let before = try #require(host.board.card("echo", "c1")?.updatedAt)
        try await Task.sleep(for: .milliseconds(20))

        // The action saves the listed card, which carries `updatedAt` with milliseconds.
        host.perform("done", cardId: "c1", pluginId: "echo")
        await waitUntil { host.pendingActions.isEmpty }
        #expect(host.board.card("echo", "c1")?.column == .done)
        #expect(try #require(host.board.card("echo", "c1")?.updatedAt) > before)
    }

    @Test func aThrownErrorFailsTheActionAndShowsOnTheCard() async throws {
        let host = loadedHost()
        _ = host.board.upsert(Card(id: "c2", title: "Two", column: .needsYou), pluginId: "echo")

        host.perform("boom", cardId: "c2", pluginId: "echo")
        await waitUntil { host.pendingActions.isEmpty }
        #expect(host.board.card("echo", "c2")?.status?.hasPrefix("Error: Error: boom") == true)
        #expect(host.runs.records.first?.outcome == .failed)
    }

    @Test func runSoonStartsOneRunAtTheEarliestRequestedTime() async throws {
        let host = loadedHost()
        _ = host.board.upsert(Card(id: "c3", title: "Three", column: .needsYou), pluginId: "echo")

        host.perform("later", cardId: "c3", pluginId: "echo")
        await waitUntil { host.runs.lastRun(of: "echo")?.outcome == .succeeded }
        #expect(host.runs.lastRun(of: "echo")?.trigger == "soon")
        #expect(host.runs.records(of: "echo").count { $0.kind == .run } == 1)
    }

    @Test func yourRetentionReplacesTheManifestDefault() {
        let host = loadedHost()
        #expect(host.retentionDays("echo") == 14)
        host.setRetentionDays(1, pluginId: "echo")
        #expect(host.retentionDays("echo") == 1)
    }

    @Test func aBrokenPluginShowsItsProblemAndDoesNotRun() {
        let host = loadedHost()
        #expect(host.plugin("broken")?.problem?.contains("dist/plugin.js is missing") == true)
        host.runNow("broken")
        #expect(host.runs.records.first?.outcome == .skipped)
    }

    @Test func aSecondRunWhileOneRunsIsSkipped() async {
        let host = loadedHost()
        host.runNow("echo")
        host.runNow("echo")
        #expect(host.runs.records.first?.message == "previous run still running")
        await waitUntil { host.running.isEmpty }
    }

    @Test func aSlotStartsAScheduledRun() async {
        let host = loadedHost()
        let calendar = Calendar.current
        let atSlot = calendar.date(bySettingHour: 10, minute: 0, second: 5, of: Date())!
        host.tick(now: atSlot.addingTimeInterval(-60))
        host.tick(now: atSlot)
        #expect(host.running.contains("echo"))
        await waitUntil { host.running.isEmpty }
        #expect(host.runs.lastRun(of: "echo")?.trigger == "schedule")
    }
}

/// The host finds each action by its id in the manifest, so a caller cannot invent one. See specs/003-custom-ui-everywhere/contracts/actions.md.
@MainActor
struct ActionLookupTests {
    private func host() -> PluginHost {
        let host = PluginHost(paths: Fixture.paths())
        host.reload()
        _ = host.board.upsert(Card(id: "c1", title: "One", column: .needsYou), pluginId: "echo")
        return host
    }

    private func answer(_ start: (PluginHost, @escaping PluginHost.ActionFinished) -> Void) async -> (Result<String?, HostError>?, PluginHost) {
        let host = host()
        var answer: Result<String?, HostError>?
        start(host) { answer = $0 }
        await waitUntil(timeout: .seconds(2)) { answer != nil }
        return (answer, host)
    }

    private func expectRefusal(_ expected: HostError, _ start: (PluginHost, @escaping PluginHost.ActionFinished) -> Void) async {
        let (answer, host) = await answer(start)
        #expect(answer == .failure(expected))
        #expect(host.runs.records.isEmpty)
        #expect(host.pendingActions.isEmpty)
    }

    @Test func anIdThatTheManifestDoesNotListIsRefused() async {
        await expectRefusal(.denied("echo has no action delete-all")) { $0.perform("delete-all", cardId: "c1", pluginId: "echo", finished: $1) }
        await expectRefusal(.denied("echo has no action delete-all")) { $0.performPluginAction("delete-all", pluginId: "echo", finished: $1) }
    }

    @Test func aPluginActionWithAnItemIsRefused() async {
        await expectRefusal(.denied("watch is not an item action")) { $0.perform("watch", cardId: "c1", pluginId: "echo", text: "a car", finished: $1) }
    }

    @Test func anItemActionWithoutAnItemIsRefused() async {
        await expectRefusal(.denied("done needs an item")) { $0.performPluginAction("done", pluginId: "echo", finished: $1) }
    }

    @Test func anItemThatThePluginDoesNotHaveIsRefused() async {
        await expectRefusal(.denied("echo has no card missing")) { $0.perform("done", cardId: "missing", pluginId: "echo", finished: $1) }
    }

    @Test func aTextActionWithBlankTextIsRefused() async {
        await expectRefusal(.failed("the action Watch needs text")) { $0.performPluginAction("watch", pluginId: "echo", text: "  ", finished: $1) }
    }
}
