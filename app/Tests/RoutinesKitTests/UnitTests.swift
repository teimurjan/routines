import Foundation
import Testing
@testable import RoutinesKit

struct ScheduleTests {
    private let calendar = Calendar(identifier: .gregorian)
    private func at(_ hour: Int, _ minute: Int, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: hour, minute: minute, second: second))!
    }

    @Test func aSlotIsDueOnceInTheRangeThatHoldsIt() {
        let slots = [ClockSlot(minute: 0), ClockSlot(minute: 30)]
        #expect(Schedule.isDue(slots, after: at(9, 59, second: 50), until: at(10, 0, second: 10), calendar: calendar))
        #expect(!Schedule.isDue(slots, after: at(10, 0, second: 10), until: at(10, 0, second: 30), calendar: calendar))
        #expect(!Schedule.isDue(slots, after: at(10, 1), until: at(10, 29), calendar: calendar))
    }

    @Test func aSleepOverManySlotsMakesOneDueCheck() {
        #expect(Schedule.isDue([ClockSlot(minute: 0)], after: at(1, 5), until: at(9, 5), calendar: calendar))
    }

    @Test func hourAndMinuteMustBothMatch() {
        let slots = [ClockSlot(minute: 45, hour: 3)]
        #expect(!Schedule.isDue(slots, after: at(2, 40), until: at(2, 50), calendar: calendar))
        #expect(Schedule.isDue(slots, after: at(3, 40), until: at(3, 50), calendar: calendar))
    }

    @Test func noSlotsMeansOnlyOnDemand() {
        #expect(!Schedule.isDue([], after: at(1, 0), until: at(9, 0), calendar: calendar))
    }
}

struct PermissionTests {
    private let check = PermissionCheck(
        permissions: Permissions(exec: ["git", "env", "claude"], hosts: ["api.github.com", "*.ycombinator.com"], paths: ["~/Projects"]),
        home: "/Users/me", alwaysAllowed: ["/tmp/routines-state"])

    @Test func onlyListedCommandsRun() {
        #expect((try? check.command(["git", "status"]).get()) != nil)
        #expect((try? check.command(["/usr/bin/git", "status"]).get()) != nil)
        #expect((try? check.command(["rm", "-rf", "/"]).get()) == nil)
        #expect((try? check.command([]).get()) == nil)
    }

    @Test func envCannotHideACommand() {
        #expect((try? check.command(["env", "-u", "X", "A=1", "claude", "-p"]).get()) != nil)
        #expect((try? check.command(["env", "A=1", "rm", "-rf", "/"]).get()) == nil)
        #expect((try? check.command(["env", "-S", "rm -rf /"]).get()) == nil)
    }

    @Test func hostsMatchExactlyOrBySubdomainPattern() {
        #expect((try? check.host(of: "https://api.github.com/repos").get()) != nil)
        #expect((try? check.host(of: "https://news.ycombinator.com/item").get()) != nil)
        #expect((try? check.host(of: "https://ycombinator.com/").get()) != nil)
        #expect((try? check.host(of: "https://evil-ycombinator.com/").get()) == nil)
        #expect((try? check.host(of: "https://github.com/").get()) == nil)
        let anyHost = PermissionCheck(permissions: Permissions(hosts: ["*"]), home: "/Users/me", alwaysAllowed: [])
        #expect((try? anyHost.host(of: "https://jobs.example.org/").get()) != nil)
    }

    @Test func pathsStayInsideTheirRoots() {
        #expect((try? check.path("~/Projects/app/file.ts").get()) == "/Users/me/Projects/app/file.ts")
        #expect((try? check.path("/tmp/routines-state/../../etc/passwd").get()) == nil)
        #expect((try? check.path("/Users/me/Projects-other/x").get()) == nil)
        #expect((try? check.path("relative/path").get()) == nil)
    }

    @Test func aSymbolicLinkCannotLeaveARoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("perm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("escape").path, withDestinationPath: "/etc")
        let linked = PermissionCheck(permissions: Permissions(), home: "/Users/me", alwaysAllowed: [root.path])
        #expect((try? linked.path(root.appendingPathComponent("escape/hosts").path).get()) == nil)
        #expect((try? linked.path(root.appendingPathComponent("inside.json").path).get()) != nil)
    }
}

@MainActor
struct BoardStoreTests {
    private func dir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("board-\(UUID().uuidString)") }

    @Test func anUpsertKeepsThePlaceOfTheCard() {
        let store = BoardStore(dir: dir())
        store.load(pluginId: "p")
        _ = store.upsert(Card(id: "a", title: "A", column: .planned), pluginId: "p")
        _ = store.upsert(Card(id: "b", title: "B", column: .planned), pluginId: "p")
        _ = store.upsert(Card(id: "a", title: "A2", column: .done), pluginId: "p")
        #expect(store.cards(of: "p").map(\.title) == ["A2", "B"])
    }

    @Test func oldDoneCardsGoAway() {
        var clock = Date()
        let store = BoardStore(dir: dir(), now: { clock })
        store.load(pluginId: "p")
        _ = store.upsert(Card(id: "old", title: "Old", column: .done), pluginId: "p")
        _ = store.upsert(Card(id: "open", title: "Open", column: .needsYou), pluginId: "p")
        clock = clock.addingTimeInterval(15 * 24 * 60 * 60)
        _ = store.upsert(Card(id: "new", title: "New", column: .planned), pluginId: "p")
        #expect(store.cards(of: "p").map(\.id) == ["open", "new"])
    }

    @Test func eachPluginKeepsItsDoneCardsForItsOwnDays() {
        var clock = Date()
        let store = BoardStore(dir: dir(), now: { clock })
        store.retentionDays = { $0 == "mail" ? 1 : 0 }
        for id in ["mail", "jobs"] {
            store.load(pluginId: id)
            _ = store.upsert(Card(id: "done", title: "Done", column: .done), pluginId: id)
            _ = store.upsert(Card(id: "open", title: "Open", column: .needsYou), pluginId: id)
        }
        clock = clock.addingTimeInterval(25 * 60 * 60)
        store.prune(pluginId: "mail")
        store.prune(pluginId: "jobs")
        #expect(store.cards(of: "mail").map(\.id) == ["open"])
        #expect(store.cards(of: "jobs").map(\.id) == ["done", "open"])
    }

    @Test func aCardWithMoreThan32KBOfDataIsRefused() throws {
        let store = BoardStore(dir: dir())
        store.load(pluginId: "p")
        let big = Card(id: "big", title: "Big", column: .planned, data: .object(["text": .string(String(repeating: "x", count: 33 * 1024))]))
        guard case .failure(let error) = store.upsert(big, pluginId: "p") else { Issue.record("the upsert passed"); return }
        #expect(error.description.contains("33803 bytes"))
        #expect(store.cards(of: "p").isEmpty)
    }

    @Test func dataSurvivesAReload() throws {
        let folder = dir()
        let data = JSONValue.object(["kind": .string("match"), "monitorId": .number(3), "tags": .array([.bool(true), .null])])
        let store = BoardStore(dir: folder)
        store.load(pluginId: "p")
        _ = store.upsert(Card(id: "a", title: "A", column: .needsYou, data: data), pluginId: "p")
        let reloaded = BoardStore(dir: folder)
        reloaded.load(pluginId: "p")
        #expect(reloaded.card("p", "a")?.data == data)
    }

    @Test func activityLeavesTheDataOut() throws {
        let card = Card(id: "a", title: "A", column: .done, data: .object(["secret": .string("only for the UI")]), updatedAt: Date())
        let activity = Activity.since(.distantPast, reader: "digest", names: ["mail": "Mail"], cards: ["mail": [card]], notifications: [], runs: [])
        let json = try #require(Reply.encode(activity))
        #expect(activity.cards.count == 1)
        #expect(!json.contains("only for the UI"))
    }

    @Test func aStoredCardWithActionsLoadsAndTheNextSaveDropsThem() throws {
        let folder = dir()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = #"[{"id":"a","title":"A","column":"needs-you","actions":[{"id":"done","label":"Done"}]}]"#
        try Data(old.utf8).write(to: folder.appendingPathComponent("p.json"))
        let store = BoardStore(dir: folder)
        store.load(pluginId: "p")
        #expect(store.card("p", "a")?.title == "A")
        _ = store.upsert(Card(id: "b", title: "B", column: .planned), pluginId: "p")
        #expect(try !String(contentsOf: folder.appendingPathComponent("p.json"), encoding: .utf8).contains("actions"))
    }

    @Test func aCorruptFileIsNotReplaced() throws {
        let folder = dir()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: folder.appendingPathComponent("p.json"))
        let store = BoardStore(dir: folder)
        store.load(pluginId: "p")
        #expect((try? store.upsert(Card(id: "a", title: "A", column: .planned), pluginId: "p").get()) == nil)
        #expect(try String(contentsOf: folder.appendingPathComponent("p.json"), encoding: .utf8) == "{not json")
    }
}

@MainActor
struct SettingsStoreTests {
    @Test func pinsKeepTheirOrderAfterAReload() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString).json")
        let store = SettingsStore(url: url)
        store.setPinned(true, pluginId: "b")
        store.setPinned(true, pluginId: "a")
        store.setPinned(true, pluginId: "b")
        store.setPinned(true, pluginId: "c")
        store.setPinned(false, pluginId: "a")
        #expect(SettingsStore(url: url).pinned == ["b", "c"])
    }
}

@MainActor
struct RunStoreTests {
    @Test func aRunThatTheAppQuitEndsAtItsLastLogLine() throws {
        let paths = Fixture.paths()
        let record = RunStore(paths: paths).start(pluginId: "p", kind: .run, trigger: "schedule")
        let lastLine = Date(timeIntervalSince1970: 1_800_000_000)
        try FileManager.default.createDirectory(at: paths.runLogDir(pluginId: "p"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: record.logFile, contents: Data())
        try FileManager.default.setAttributes([.modificationDate: lastLine], ofItemAtPath: record.logFile)

        let reloaded = try #require(RunStore(paths: paths).records.first)
        #expect(reloaded.outcome == .failed)
        #expect(abs((reloaded.endedAt ?? .distantPast).timeIntervalSince(lastLine)) < 1)
    }
}

@MainActor
struct PageStoreTests {
    private func dir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("pages-\(UUID().uuidString)") }

    @Test func theSameBlocksKeepTheTimeOfTheLastChange() {
        var clock = Date(timeIntervalSince1970: 1_000)
        let folder = dir()
        let store = PageStore(dir: folder, now: { clock })
        _ = store.publish([.markdown("Hi")], pluginId: "p")
        clock = clock.addingTimeInterval(60)
        _ = store.publish([.markdown("Hi")], pluginId: "p")
        #expect(store.page(of: "p")?.updatedAt == Date(timeIntervalSince1970: 1_000))
        _ = store.publish([.status(PageStatus(state: .ok, label: "Up"))], pluginId: "p")
        #expect(store.page(of: "p")?.updatedAt == clock)

        let reloaded = PageStore(dir: folder)
        reloaded.load(pluginId: "p")
        #expect(reloaded.page(of: "p")?.blocks == [.status(PageStatus(state: .ok, label: "Up"))])
    }

    @Test func blocksDecodeFromTheJSONOfThePlugin() throws {
        let json = #"[{"type":"markdown","text":"Hi"},{"type":"status","state":"error","label":"Down","detail":"no tmux"}]"#
        let blocks = try JSONDecoder().decode([PageBlock].self, from: Data(json.utf8))
        #expect(blocks == [.markdown("Hi"), .status(PageStatus(state: .error, label: "Down", detail: "no tmux"))])
        #expect((try? JSONDecoder().decode([PageBlock].self, from: Data(#"[{"type":"html","text":"<b>"}]"#.utf8))) == nil)
    }
}

struct ToolGuardTests {
    @Test func onlyAnExactInputPasses() {
        let allowed: [[String: JSONValue]] = [["channel_id": .string("C1"), "message": .string("hi")]]
        #expect(ToolGuard.inputAllowed(["channel_id": .string("C1"), "message": .string("hi")], allowedInputs: allowed))
        #expect(!ToolGuard.inputAllowed(["channel_id": .string("C1"), "message": .string("other")], allowedInputs: allowed))
        #expect(!ToolGuard.inputAllowed(["channel_id": .string("C1"), "message": .string("hi"), "extra": .bool(true)], allowedInputs: allowed))
    }

    @Test func anUnreadableCallIsBlocked() {
        #expect(ToolGuard.run(stdin: Data("nope".utf8), environment: [:]).code == 2)
        let input = Data(#"{"tool_input":{"a":"1"}}"#.utf8)
        #expect(ToolGuard.run(stdin: input, environment: ["ROUTINES_TOOL_GUARD": #"[{"a":"1"}]"#]).code == 0)
        #expect(ToolGuard.run(stdin: input, environment: [:]).code == 2)
    }
}

/// Constitution R1: the host source names no plugin.
/// The host must not name a plugin of `ROUTINES_PLUGINS_DIR`.
struct HostIsGenericTests {
    static let pluginsDir = ProcessInfo.processInfo.environment["ROUTINES_PLUGINS_DIR"]

    @Test(.enabled(if: pluginsDir != nil, "ROUTINES_PLUGINS_DIR is not set"))
    func theHostSourceNamesNoPluginId() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let ids = ((try? FileManager.default.contentsOfDirectory(atPath: Self.pluginsDir ?? "")) ?? []).filter { !$0.hasPrefix(".") }
        #expect(!ids.isEmpty)
        let sources = FileManager.default.enumerator(at: app.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            for id in ids {
                let pattern = "\"\(id)\""
                #expect(!text.contains(pattern), "\(file.lastPathComponent) names the plugin \(id)")
            }
        }
    }
}

struct ExternalActionTests {
    private let manifest = Manifest(
        id: "mail", name: "Mail", permissions: Permissions(external: ["trash-numbers"]),
        actions: [
            CardAction(id: "trash-numbers", label: "Trash by number"), CardAction(id: "reply", label: "Reply"),
            CardAction(id: "trash", label: "Trash", target: .item),
        ])

    @Test func aURLRoundTrips() {
        let action = ExternalAction(pluginId: "mail", actionId: "trash-numbers", text: "41 43-45", replyFile: "/data/replies/a.txt")
        #expect(ExternalAction.parse(action.url) == action)
    }

    @Test func onlyListedActionsRunFromOutside() {
        let allowed = ExternalAction(pluginId: "mail", actionId: "trash-numbers", text: "1", replyFile: "/data/replies/a.txt")
        let reply = ExternalAction(pluginId: "mail", actionId: "reply", text: "delete all", replyFile: nil)
        let escape = ExternalAction(pluginId: "mail", actionId: "trash-numbers", text: "1", replyFile: "/data/replies/../../etc/x")
        #expect((try? allowed.check(manifest, repliesDir: "/data/replies").get()) != nil)
        #expect((try? reply.check(manifest, repliesDir: "/data/replies").get()) == nil)
        #expect((try? escape.check(manifest, repliesDir: "/data/replies").get()) == nil)
    }

    @Test func anItemActionNeverRunsFromOutside() {
        var listed = manifest
        listed.permissions.external.append("trash")
        let request = ExternalAction(pluginId: "mail", actionId: "trash", text: nil, replyFile: nil)
        #expect(throws: HostError.denied("trash needs an item")) { try request.check(listed, repliesDir: "/data/replies").get() }
    }
}

struct ManifestTests {
    @Test func anActionWithoutATargetIsAPluginAction() throws {
        let decode = { (json: String) in try JSONDecoder().decode(Manifest.self, from: Data(json.utf8)) }
        let actions = try decode(#"{"id":"a","name":"A","actions":[{"id":"go","label":"Go"},{"id":"done","label":"Done","target":"item"}]}"#).actions
        #expect(actions.map(\.isItemAction) == [false, true])
    }

    @Test func anEmojiIsOptionalAndAnEmptyOneCountsAsNone() throws {
        let decode = { (json: String) in try JSONDecoder().decode(Manifest.self, from: Data(json.utf8)) }
        #expect(try decode(#"{"id":"a","name":"A","emoji":"📧"}"#).emoji == "📧")
        #expect(try decode(#"{"id":"a","name":"A","emoji":""}"#).emoji == nil)
        #expect(try decode(#"{"id":"a","name":"A"}"#).emoji == nil)
    }

    @Test func aManifestWithTheOldViewKeysStillDecodes() throws {
        let decode = { (json: String) in try JSONDecoder().decode(Manifest.self, from: Data(json.utf8)) }
        let old = try decode(#"{"id":"a","name":"A","views":["page","board"],"doneCards":{"retentionDays":1,"deletable":false}}"#)
        #expect(old.doneCards == DoneCards(retentionDays: 1))
    }

    @Test func aPluginShowsInTheSidebarUnlessItIsHidden() throws {
        let decode = { (json: String) in try JSONDecoder().decode(Manifest.self, from: Data(json.utf8)) }
        #expect(try decode(#"{"id":"a","name":"A"}"#).hidden == false)
        #expect(try decode(#"{"id":"a","name":"A","hidden":true}"#).hidden == true)
    }

    @Test func doneCardsDefaultToTwoWeeks() throws {
        let decode = { (json: String) in try JSONDecoder().decode(Manifest.self, from: Data(json.utf8)) }
        #expect(try decode(#"{"id":"a","name":"A"}"#).doneCards == DoneCards(retentionDays: 14))
        #expect(try decode(#"{"id":"a","name":"A","doneCards":{"retentionDays":-3}}"#).doneCards == DoneCards(retentionDays: 0))
    }
}

struct ActivityTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func theReaderGetsTheNewWorkOfTheOtherLoadedPlugins() {
        let new = start.addingTimeInterval(60)
        let old = start.addingTimeInterval(-60)
        let card = { (id: String, at: Date) in Card(id: id, title: id, body: String(repeating: "x", count: 900), column: .done, updatedAt: at) }
        let run = { (pluginId: String, outcome: RunRecord.Outcome) in
            RunRecord(id: UUID(), pluginId: pluginId, kind: .run, trigger: "schedule", startedAt: new, outcome: outcome, logFile: "")
        }
        let activity = Activity.since(
            start, reader: "digest", names: ["mail": "Mail", "digest": "Digest"],
            cards: ["mail": [card("new", new), card("old", old)], "digest": [card("own", new)], "gone": [card("gone", new)]],
            notifications: [HostNotification(id: UUID(), pluginId: "mail", title: "Mail", body: "2 trashed", cardId: nil, at: new)],
            runs: [run("mail", .failed), run("mail", .succeeded), run("digest", .failed)])

        #expect(activity.cards.map(\.title) == ["new"])
        #expect(activity.cards.first?.body?.count == Activity.bodyLimit)
        #expect(activity.notifications.map(\.plugin) == ["Mail"])
        #expect(activity.failedRuns.count == 1)
    }
}

struct BrowserStoreTests {
    @Test func aProfileKeepsItsStoreAcrossCallsAndPluginsDoNotShare() {
        #expect(BrowserService.storeId(pluginId: "site", profile: "main") == BrowserService.storeId(pluginId: "site", profile: "main"))
        #expect(BrowserService.storeId(pluginId: "site", profile: "main") != BrowserService.storeId(pluginId: "other", profile: "main"))
    }
}
