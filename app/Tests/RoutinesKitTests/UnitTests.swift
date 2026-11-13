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

    @Test func aPluginReadsButDoesNotWriteTheHostFiles() throws {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("data-\(UUID().uuidString)").path
        let guarded = PermissionCheck(
            permissions: Permissions(paths: [data]), home: "/Users/me", alwaysAllowed: [], protected: PermissionCheck.hostFiles(dataDir: data))
        #expect((try? guarded.path(data + "/actionables/1.json").get()) != nil)
        #expect(throws: HostError.self) { try guarded.writablePath(data + "/actionables/1.json").get() }
        #expect(throws: HostError.self) { try guarded.writablePath(data + "/settings.json").get() }
        #expect(throws: HostError.self) { try guarded.writablePath(data, removing: true).get() }
        #expect((try? guarded.writablePath(data + "/mine/notes.txt").get()) != nil)
        guard case .failure(let error) = guarded.writablePath(data + "/memory/entries.json") else { return }
        #expect(error.description.contains("the host owns"))
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

/// The board calls of the plugins of today keep working on actionables (research.md, section 16).
@MainActor
struct BoardAdapterTests {
    private func dir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("board-\(UUID().uuidString)") }

    @Test func anUpsertKeepsThePlaceOfTheCard() {
        let board = BoardAdapter(store: ActionableStore(dir: dir()))
        board.upsert(Card(id: "a", title: "A", column: .planned), pluginId: "p", trigger: "t")
        board.upsert(Card(id: "b", title: "B", column: .planned), pluginId: "p", trigger: "t")
        board.upsert(Card(id: "a", title: "A2", column: .done), pluginId: "p", trigger: "t")
        #expect(board.cards(of: "p").map(\.title) == ["A2", "B"])
    }

    @Test func aNewColumnAddsABoardStepAndTheSameColumnAddsNone() throws {
        let store = ActionableStore(dir: dir())
        let board = BoardAdapter(store: store)
        board.upsert(Card(id: "a", title: "A", column: .planned), pluginId: "p", trigger: "t")
        board.upsert(Card(id: "a", title: "A again", column: .planned), pluginId: "p", trigger: "t")
        board.upsert(Card(id: "a", title: "A", column: .needsYou), pluginId: "p", trigger: "t")
        let actionable = try #require(store.find(source: "p", key: "a"))
        #expect(actionable.steps.map(\.action) == [.created, .board])
        #expect(actionable.state == .waitingOnYou)
        #expect(actionable.owner == "p" && actionable.kind == "p")
    }

    @Test func aRemovedCardIsDroppedAndLeavesTheBoard() throws {
        let store = ActionableStore(dir: dir())
        let board = BoardAdapter(store: store)
        board.upsert(Card(id: "a", title: "A", column: .planned), pluginId: "p", trigger: "t")
        _ = board.remove("a", pluginId: "p", trigger: "t")
        #expect(board.cards(of: "p").isEmpty)
        #expect(store.find(source: "p", key: "a")?.state == .dropped)
    }

    @Test func oldDoneCardsGoAway() {
        let clock = FakeClock()
        let store = ActionableStore(dir: dir(), now: clock.function)
        let board = BoardAdapter(store: store)
        board.upsert(Card(id: "old", title: "Old", column: .done), pluginId: "p", trigger: "t")
        board.upsert(Card(id: "open", title: "Open", column: .needsYou), pluginId: "p", trigger: "t")
        clock.advance(15 * 24 * 60 * 60)
        board.upsert(Card(id: "new", title: "New", column: .planned), pluginId: "p", trigger: "t")
        store.prune()
        #expect(board.cards(of: "p").map(\.id) == ["open", "new"])
    }

    @Test func eachPluginKeepsItsDoneCardsForItsOwnDays() {
        let clock = FakeClock()
        let store = ActionableStore(dir: dir(), now: clock.function)
        store.retentionDays = { $0 == "mail" ? 1 : 0 }
        let board = BoardAdapter(store: store)
        for id in ["mail", "jobs"] {
            board.upsert(Card(id: "done", title: "Done", column: .done), pluginId: id, trigger: "t")
            board.upsert(Card(id: "open", title: "Open", column: .needsYou), pluginId: id, trigger: "t")
        }
        clock.advance(25 * 60 * 60)
        store.prune()
        #expect(board.cards(of: "mail").map(\.id) == ["open"])
        #expect(board.cards(of: "jobs").map(\.id) == ["done", "open"])
    }

    @Test func aCardWithMoreThan32KBOfDataIsRefused() throws {
        let board = BoardAdapter(store: ActionableStore(dir: dir()))
        let big = Card(id: "big", title: "Big", column: .planned, data: .object(["text": .string(String(repeating: "x", count: 33 * 1024))]))
        guard case .failure(let error) = board.upsert(big, pluginId: "p", trigger: "t") else { Issue.record("the upsert passed"); return }
        #expect(error.description.contains("33803 bytes"))
        #expect(board.cards(of: "p").isEmpty)
    }

    @Test func dataSurvivesAReload() throws {
        let folder = dir()
        let data = JSONValue.object(["kind": .string("match"), "monitorId": .number(3), "tags": .array([.bool(true), .null])])
        BoardAdapter(store: ActionableStore(dir: folder)).upsert(Card(id: "a", title: "A", column: .needsYou, data: data), pluginId: "p", trigger: "t")
        #expect(BoardAdapter(store: ActionableStore(dir: folder)).card("p", "a")?.data == data)
    }

    @Test func activityLeavesTheDataOut() throws {
        let card = Card(id: "a", title: "A", column: .done, data: .object(["secret": .string("only for the UI")]), updatedAt: Date())
        let activity = Activity.since(.distantPast, reader: "digest", names: ["mail": "Mail"], cards: ["mail": [card]], notifications: [], runs: [])
        let json = try #require(Reply.encode(activity))
        #expect(activity.cards.count == 1)
        #expect(!json.contains("only for the UI"))
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

/// Constitution R1 and FR-011: the host source names no plugin, no kind and no transition.
/// The host must not name a plugin of `ROUTINES_PLUGINS_DIR`, or a kind or a transition of their manifests.
struct HostIsGenericTests {
    static let pluginsDir = ProcessInfo.processInfo.environment["ROUTINES_PLUGINS_DIR"]
    static let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let newFolders = ["Actionables", "Entrance", "Polling", "Memory"]

    private static func sources() -> [URL] {
        FileManager.default.enumerator(at: app.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
    }

    @Test func theCheckReadsTheNewFeatureFolders() {
        let folders = Set(Self.sources().map { $0.deletingLastPathComponent().lastPathComponent })
        for folder in Self.newFolders { #expect(folders.contains(folder), "the check does not read Kit/\(folder)") }
    }

    @Test(.enabled(if: pluginsDir != nil, "ROUTINES_PLUGINS_DIR is not set"))
    func theHostSourceNamesNoPluginKindOrTransition() throws {
        let dir = Self.pluginsDir ?? ""
        let ids = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") }
        #expect(!ids.isEmpty)
        let manifests = ids.compactMap { id in
            (try? Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent("\(id)/plugin.json"))).flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }
        }
        let names = Set(ids + manifests.flatMap { $0.kinds + $0.handles.map(\.kind) + $0.transitions.map(\.id) })
        for file in Self.sources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for name in names {
                #expect(!text.contains("\"\(name)\""), "\(file.lastPathComponent) names \(name) of a plugin")
            }
        }
    }
}

struct ExternalActionTests {
    @Test func aURLRoundTrips() {
        let action = ExternalAction(pluginId: "mail", actionId: "trash-numbers", text: "41 43-45", replyFile: "/data/replies/a.txt")
        #expect(ExternalAction.parse(action.url) == action)
        let transition = ExternalAction(pluginId: "asker", actionId: "answer", item: "9", text: "use the staging key", replyFile: nil)
        #expect(ExternalAction.parse(transition.url) == transition)
    }

    @Test func anAnswerGoesOnlyToTheRepliesFolder() {
        let inside = ExternalAction(pluginId: "mail", actionId: "a", text: nil, replyFile: "/data/replies/a.txt")
        let escape = ExternalAction(pluginId: "mail", actionId: "a", text: nil, replyFile: "/data/replies/../../etc/x")
        #expect((try? inside.checkReply(repliesDir: "/data/replies").get()) != nil)
        #expect((try? escape.checkReply(repliesDir: "/data/replies").get()) == nil)
    }

    @Test func anItemMakesATransitionTriggerFromOutside() {
        let at = Date()
        let trigger = ExternalAction(pluginId: "asker", actionId: "answer", item: "9", text: "yes", replyFile: nil).trigger(at: at)
        #expect(trigger.source == .external && trigger.work == .transition && trigger.actionable == "9" && trigger.transition == "answer")
        #expect(ExternalAction(pluginId: "mail", actionId: "go", text: nil, replyFile: nil).trigger(at: at).work == .action)
    }

    @MainActor
    @Test func aScriptMovesOnlyWhatTheManifestAllows() async throws {
        let host = PluginHost.actionables()
        let bug = host.seed(kind: "bug", owner: "asker", state: .waitingOnYou, data: .object(["repo": .string("r"), "details": .string("d")]))
        let working = host.seed(kind: "bug", owner: "asker", state: .working)
        let note = host.seed(kind: "note", owner: "sender", state: .ready)
        let external = { (action: String, item: String, text: String?) in
            await host.answer(of: ExternalAction(pluginId: "asker", actionId: action, item: item, text: text, replyFile: nil).trigger(at: host.now()))
        }
        #expect(await external("merge", working.id, nil) == .failure(.failed("asker does not allow merge from outside the app")))
        #expect(await external("approve", bug.id, nil) == .failure(.failed("Approve starts only from a press in the app")))
        #expect(await external("drop", note.id, nil) == .failure(.failed("asker does not own actionable \(note.id)")))
        #expect(try await external("answer", bug.id, "use the staging key").get() == "use the staging key")
        #expect(host.actionables.actionable(bug.id)?.state == .working)
    }

    @MainActor
    @Test func theReplyFileHoldsTheStatusOrTheRefusal() async throws {
        let host = PluginHost.actionables()
        let bug = host.seed(kind: "bug", owner: "asker", state: .working, data: .object(["repo": .string("r"), "details": .string("d")]))
        let reply = host.paths.file("replies/a.txt").path
        host.performExternal(ExternalAction(pluginId: "asker", actionId: "merge", item: bug.id, text: nil, replyFile: reply))
        await waitUntil { FileManager.default.fileExists(atPath: reply) }
        #expect(try String(contentsOfFile: reply, encoding: .utf8) == "Error: asker does not allow merge from outside the app")
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

    @Test func theNewFieldsDecodeAndNameTheRole() throws {
        let decode = { (json: String) in try JSONDecoder().decode(Manifest.self, from: Data(json.utf8)) }
        let routine = try decode(#"{"id":"a","name":"A","handles":[{"kind":"bug","states":["new"]}],"kinds":["bug"],"transitions":[{"id":"go","label":"Go","from":["new"],"risk":"outward","confirm":true}]}"#)
        #expect(routine.role == .routine)
        #expect(routine.transitions.first?.risk == .outward && routine.transitions.first?.needsConfirmation == true)
        #expect(try decode(#"{"id":"s","name":"S","source":{"kinds":["note"],"tools":["mcp__x__read"]}}"#).role == .source)
        #expect(try decode(#"{"id":"o","name":"O"}"#).role == .legacy)
        #expect(throws: DecodingError.self) { try decode(#"{"id":"a","name":"A","transitions":[{"id":"go","label":"Go","from":["new"]}]}"#) }
    }

    @Test func theItemActionsOfAPluginOfTodayAreOutwardTransitions() {
        let manifest = Manifest(id: "old", name: "Old", actions: [CardAction(id: "done", label: "Done", target: .item), CardAction(id: "go", label: "Go")])
        #expect(manifest.effectiveTransitions.map(\.id) == ["done"])
        #expect(manifest.transition("done")?.risk == .outward)
        #expect(manifest.transition("done")?.from == Actionable.State.open)
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
