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

    private func run(_ host: PluginHost, _ id: String = "echo") async {
        host.submit(.run(id, source: .clock, at: Date()))
        await waitUntil { host.running.isEmpty }
    }

    @Test func aRunUsesTheHostAPIsAndTheWebPolyfills() async throws {
        let host = loadedHost()
        await run(host)

        let record = try #require(host.runs.lastRun(of: "echo"))
        #expect(record.outcome == .succeeded)
        #expect(record.message == "hi")
        let written = try String(contentsOfFile: host.paths.stateDir + "/echo.txt", encoding: .utf8)
        #expect(written == "schedule:hey:1:2:aGk=")
        #expect(host.notifications.items.first?.cardId == "c1")
        #expect(host.pages.page(of: "echo")?.blocks == [.status(PageStatus(state: .ok, label: "Up")), .markdown("Hello")])
        #expect(RunLog.read(record.logFile).contains("logged {\"a\":1}"))
    }

    @Test func theManifestLimitsCommandsAndPaths() async throws {
        let host = loadedHost()
        await run(host)

        let status = try #require(host.boardAdapter.card("echo", "c1")?.status)
        #expect(status.contains("the command rm is not in permissions.exec"))
        #expect(status.contains("the path /etc/hosts is not in permissions.paths"))
    }

    @Test func anItemActionMovesItsCardAndSetsTheStatus() async throws {
        let host = loadedHost()
        await run(host)

        #expect(try await host.press("done", card: "c1", of: "echo", text: "now").get() == "moved now")
        let card = try #require(host.boardAdapter.card("echo", "c1"))
        #expect(card.column == .done)
        #expect(card.status == "moved now")
    }

    @Test func aPluginActionCallsOnPluginActionAndShowsItsAnswer() async throws {
        let host = loadedHost()
        #expect(try await host.press("watch", of: "echo", text: "a car").get() == "watch a car")
        #expect(host.pluginActionStatus["echo"] == "watch a car")
        #expect(host.runs.records.first?.trigger == "watch")
    }

    @Test func aCardFromTheListCanBeSavedAgain() async throws {
        let host = loadedHost()
        await run(host)
        let before = try #require(host.boardAdapter.card("echo", "c1")?.updatedAt)
        try await Task.sleep(for: .milliseconds(20))

        // The action saves the listed card, which carries `updatedAt` with milliseconds.
        _ = await host.press("done", card: "c1", of: "echo")
        #expect(host.boardAdapter.card("echo", "c1")?.column == .done)
        #expect(try #require(host.boardAdapter.card("echo", "c1")?.updatedAt) > before)
    }

    @Test func aThrownErrorFailsTheActionAndShowsOnTheCard() async throws {
        let host = loadedHost()
        host.boardAdapter.upsert(Card(id: "c2", title: "Two", column: .needsYou), pluginId: "echo", trigger: "test")

        let answer = await host.press("boom", card: "c2", of: "echo")
        #expect((try? answer.get()) == nil)
        #expect(host.boardAdapter.card("echo", "c2")?.status?.hasPrefix("Error: Error: boom") == true)
        #expect(host.runs.records.first?.outcome == .failed)
    }

    @Test func runSoonStartsARunWithTheSourceSelf() async throws {
        let host = loadedHost()
        host.boardAdapter.upsert(Card(id: "c3", title: "Three", column: .needsYou), pluginId: "echo", trigger: "test")

        _ = await host.press("later", card: "c3", of: "echo")
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

    @Test func aBrokenPluginShowsItsProblemAndDoesNotRun() throws {
        let host = loadedHost()
        #expect(host.plugin("broken")?.problem?.contains("dist/plugin.js is missing") == true)
        let decision = host.submit(.run("broken", source: .ui, at: Date()))
        #expect(decision.refusal?.description.contains("dist/plugin.js is missing") == true)
        #expect(host.runs.records.isEmpty)
        #expect(try #require(host.decisions.records(on: Date()).last).decision == "refuse")
    }

    @Test func aRunTriggerDuringARunQueuesOneMoreRun() async {
        let host = loadedHost()
        #expect(host.submit(.run("echo", source: .clock, at: Date())) == .startRun)
        #expect(host.submit(.run("echo", source: .clock, at: Date())) == .queueRun)
        #expect(host.submit(.run("echo", source: .clock, at: Date())) == .merge)
        await waitUntil { host.running.isEmpty && host.runs.records(of: "echo").count == 2 }
        #expect(host.runs.records(of: "echo").count == 2)
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
        host.boardAdapter.upsert(Card(id: "c1", title: "One", column: .needsYou), pluginId: "echo", trigger: "test")
        return host
    }

    private func expectRefusal(_ expected: String, _ press: (PluginHost) async -> Result<String?, HostError>) async {
        let host = host()
        #expect(await press(host) == .failure(.failed(expected)))
        #expect(host.runs.records.isEmpty)
        #expect(host.pendingActions.isEmpty)
    }

    @Test func anIdThatTheManifestDoesNotListIsRefused() async {
        await expectRefusal("echo has no transition delete-all") { await $0.press("delete-all", card: "c1", of: "echo") }
        await expectRefusal("echo has no action delete-all") { await $0.press("delete-all", of: "echo") }
    }

    @Test func aPluginActionWithAnItemIsRefused() async {
        await expectRefusal("echo has no transition watch") { await $0.press("watch", card: "c1", of: "echo", text: "a car") }
    }

    @Test func anItemActionWithoutAnItemIsRefused() async {
        await expectRefusal("done needs an item") { await $0.press("done", of: "echo") }
    }

    @Test func anItemThatThePluginDoesNotHaveIsRefused() async {
        await expectRefusal("there is no actionable missing") {
            await $0.answer(of: .transition("done", of: "missing", routine: "echo", source: .ui, at: Date()))
        }
    }

    @Test func aTextActionWithBlankTextIsRefused() async {
        await expectRefusal("the transition Watch needs text") { await $0.press("watch", of: "echo", text: "  ") }
    }
}
