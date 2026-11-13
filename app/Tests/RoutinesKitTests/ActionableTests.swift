import Foundation
import Testing
@testable import RoutinesKit

private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("actionables-\(UUID().uuidString)") }

private func draft(_ action: Step.Action = .created) -> Step.Draft { Step.Draft(action: action, actor: "test", trigger: "t") }

private func json(_ text: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

@MainActor
struct ActionableStoreTests {
    private func create(_ store: ActionableStore, key: String = "k", data: JSONValue = .object([:])) -> Result<Actionable, HostError> {
        store.create(kind: "note", source: "s", dedupeKey: key, owner: "r", state: .new, title: "T", step: draft()) { $0.data = data }
    }

    @Test func oneStepWritesOneFile() throws {
        let dir = folder()
        let store = ActionableStore(dir: dir)
        let created = try create(store).get()
        let before = try Data(contentsOf: dir.appendingPathComponent("\(created.id).json"))
        try store.update(created.id, step: draft(.transition("start"))) { $0.state = .working }.get()
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(files == ["1.json", "next-id.json"])
        #expect(try Data(contentsOf: dir.appendingPathComponent("1.json")) != before)
        #expect(store.actionable("1")?.steps.map(\.id) == ["1.1", "1.2"])
        #expect(store.actionable("1")?.steps.last.map { [$0.from, $0.to] } == [.new, .working])
    }

    @Test func aReloadGivesEqualActionables() throws {
        let dir = folder()
        let store = ActionableStore(dir: dir)
        _ = try create(store, data: json(#"{"repo":"a","n":[1,true,null]}"#)).get()
        try store.update("1", step: draft(.transition("start"))) { $0.state = .working; $0.links = [CardLink(label: "PR", url: "https://x.y/1")] }.get()
        let reloaded = ActionableStore(dir: dir)
        #expect(reloaded.all.count == 1)
        let stored = try #require(store.actionable("1"))
        let again = try #require(reloaded.actionable("1"))
        #expect(again.steps.map(\.id) == stored.steps.map(\.id))
        #expect(again.data == stored.data && again.links == stored.links && again.state == stored.state && again.owner == stored.owner)
        #expect(reloaded.owned(by: "r").map(\.id) == ["1"])
    }

    @Test func aCorruptFileStaysAndBlocksWritesToIt() throws {
        let dir = folder()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: dir.appendingPathComponent("4.json"))
        let store = ActionableStore(dir: dir)
        #expect(store.errors["4"] != nil)
        #expect((try? store.update("4", step: draft(.board)) { $0.state = .done }.get()) == nil)
        #expect(try String(contentsOf: dir.appendingPathComponent("4.json"), encoding: .utf8) == "{not json")
        // A new actionable never takes the id of the corrupt file.
        #expect(try create(store).get().id == "5")
    }

    @Test func aSecondCreateWithTheSameSourceAndKeyIsRefused() throws {
        let store = ActionableStore(dir: folder())
        _ = try create(store).get()
        #expect((try? create(store).get()) == nil)
        #expect(store.all.count == 1)
        #expect(store.find(source: "s", key: "k")?.id == "1")
    }

    @Test func dataOver32KBIsRefused() {
        let store = ActionableStore(dir: folder())
        guard case .failure(let error) = create(store, data: .object(["x": .string(String(repeating: "x", count: 33 * 1024))])) else {
            Issue.record("the create passed")
            return
        }
        #expect(error.description.contains("At most 32 KB as JSON"))
    }

    @Test func aClosedActionableGoesAfterItsRetention() throws {
        let clock = FakeClock()
        let store = ActionableStore(dir: folder(), now: clock.function)
        store.retentionDays = { _ in 2 }
        _ = try create(store, key: "open").get()
        let closed = try create(store, key: "closed").get()
        try store.update(closed.id, step: draft(.transition("drop"))) { $0.state = .dropped }.get()
        clock.advance(24 * 60 * 60)
        store.prune()
        #expect(store.all.count == 2)
        clock.advance(24 * 60 * 60)
        store.prune()
        #expect(store.all.map(\.dedupeKey) == ["open"])
    }
}

struct KindSchemaTests {
    private func schema(_ text: String) throws -> KindSchema { try KindSchema.parse(json(text)).get() }

    private func fault(_ schema: KindSchema, _ value: String) -> String? {
        if case .failure(let error) = schema.validate(json(value)) { return error.description }
        return nil
    }

    @Test func typesPropertiesAndRequiredFieldsAreChecked() throws {
        let bug = try schema(#"{"type":"object","required":["repo","details"],"properties":{"repo":{"type":"string"},"details":{"type":"string","maxLength":5}},"additionalProperties":false}"#)
        #expect(fault(bug, #"{"repo":"a","details":"b"}"#) == nil)
        #expect(fault(bug, #"{"repo":1,"details":"b"}"#) == "data.repo must be a string")
        #expect(fault(bug, #"{"repo":"a"}"#) == "data.details is required")
        #expect(fault(bug, #"{"repo":"a","details":"too long"}"#) == "data.details must have at most 5 characters")
        #expect(fault(bug, #"{"repo":"a","details":"b","extra":true}"#) == "data.extra is not allowed")
        #expect(fault(bug, #"[]"#) == "data must be an object")
    }

    @Test func itemsAndEnumAreChecked() throws {
        let list = try schema(#"{"type":"object","properties":{"tags":{"type":"array","items":{"type":"string","enum":["a","b"]}},"n":{"type":"integer"}}}"#)
        #expect(fault(list, #"{"tags":["a","b"],"n":3}"#) == nil)
        #expect(fault(list, #"{"tags":["a","c"]}"#) == "data.tags[1] must be one of a, b")
        #expect(fault(list, #"{"n":1.5}"#) == "data.n must be an integer")
    }

    @Test func aSchemaWithAnotherKeywordIsRefused() {
        #expect(throws: HostError.self) { try schema(#"{"type":"string","pattern":"^a"}"#) }
        #expect(throws: HostError.self) { try schema(#"{"type":"object","properties":{"x":{"minLength":1}}}"#) }
        #expect((try? schema(#"{"type":"string","description":"a note"}"#)) != nil)
    }

    @Test func anUndeclaredKindAcceptsAnyObject() {
        #expect((try? HandlesTable.empty.schema(of: "anything").validate(json(#"{"a":[1,{"b":null}]}"#)).get()) != nil)
        #expect((try? HandlesTable.empty.schema(of: "anything").validate(json("3")).get()) == nil)
    }
}

@MainActor
struct HandlesTests {
    private func entry(_ id: String, kinds: [String] = [], handles: [Handle] = [], schemas: [String: KindSchema] = [:]) -> PluginEntry {
        var entry = PluginEntry(manifest: Manifest(id: id, name: id, handles: handles, kinds: kinds), dir: "/p/\(id)")
        entry.kinds = schemas
        return entry
    }

    @Test func theSecondRoutineThatHandlesAPairIsRefused() {
        let table = Handles.build([
            entry("first", handles: [Handle(kind: "bug", states: [.new])]),
            entry("second", handles: [Handle(kind: "bug", states: [.new, .ready])]),
        ])
        #expect(table.handler(kind: "bug", state: .new) == "first")
        #expect(table.handler(kind: "bug", state: .ready) == nil)
        #expect(table.problems["second"] == "first already handles bug in new")
    }

    @Test func aKindThatTwoPluginsDeclareIsRefused() {
        let table = Handles.build([entry("a", kinds: ["bug"], schemas: ["bug": .anyObject]), entry("b", kinds: ["bug"])])
        #expect(table.problems["b"] == "the kind bug is already declared by a")
        #expect(table.problems["a"] == nil)
    }

    @Test func aMissingKindsEntryIsAProblem() throws {
        let dir = folder()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try Data(#"{"id":"k","name":"K","kinds":["bug","note"]}"#.utf8).write(to: dir.appendingPathComponent("plugin.json"))
        try Data("".utf8).write(to: dir.appendingPathComponent("dist/plugin.js"))
        try Data(#"{"bug":{"type":"object"}}"#.utf8).write(to: dir.appendingPathComponent("dist/kinds.json"))
        let loaded = PluginCatalog.load(dir: dir.path, folder: "k")
        #expect(loaded.problem == "dist/kinds.json has no schema for the kind note")
    }

    @Test func aSourceWithTransitionsAndAnEmptyFromAreProblems() {
        let source = Manifest(id: "s", name: "S", transitions: [TransitionDeclaration(id: "go", label: "Go", from: [.new], risk: .read)], source: SourceDeclaration(kinds: [], tools: []))
        #expect(ManifestRules.problem(source) == "a source cannot have handles or transitions")
        let empty = Manifest(id: "r", name: "R", transitions: [TransitionDeclaration(id: "go", label: "Go", from: [], risk: .read)])
        #expect(ManifestRules.problem(empty) == "the transition go starts from no state")
        let twice = Manifest(id: "r", name: "R", actions: [CardAction(id: "go", label: "Go")], transitions: [TransitionDeclaration(id: "go", label: "Go", from: [.new], risk: .read)])
        #expect(ManifestRules.problem(twice) == "the id go is used twice in transitions and actions")
    }

    @Test func theFixturesLoadWithoutAProblem() {
        let host = PluginHost.actionables()
        #expect(host.plugins.map(\.id).sorted() == ["asker", "notes-source", "sender"])
        #expect(host.plugins.allSatisfy { $0.problem == nil })
        #expect(host.handles.handler(kind: "bug", state: .new) == "asker")
        #expect(host.handles.handler(kind: "note", state: .ready) == "sender")
    }
}

/// One test per acceptance scenario of US1.
@MainActor
struct MoveTests {
    private let bugData = JSONValue.object(["repo": .string("demo"), "details": .string("x")])

    private func manifest(_ host: PluginHost, _ id: String) -> Manifest { host.plugin(id)!.manifest }

    @Test func theOwnerMovesReadyToWorkingWithOneStep() throws {
        let host = PluginHost.actionables()
        let note = host.seed(kind: "note", owner: "sender", state: .ready)
        let moved = try host.actionables.apply(Move(to: .working), transition: "start", to: note.id, by: "sender", manifest: manifest(host, "sender"), trigger: "t").get()
        #expect(moved.steps.count == 2)
        #expect(moved.steps.last?.action == .transition("start"))
        #expect(moved.steps.last.map { [$0.from, $0.to] } == [.ready, .working])
    }

    @Test func anotherOwnerIsRefusedWithNoStep() {
        let host = PluginHost.actionables()
        let note = host.seed(kind: "note", owner: "sender", state: .ready)
        let moved = host.actionables.apply(Move(to: .working), transition: "drop", to: note.id, by: "asker", manifest: manifest(host, "asker"), trigger: "t")
        #expect(moved == .failure(.failed("asker does not own actionable \(note.id)")))
        #expect(host.actionables.actionable(note.id)?.steps.count == 1)
    }

    @Test func anUnlistedTransitionAndAWrongStateAreRefused() {
        let host = PluginHost.actionables()
        let note = host.seed(kind: "note", owner: "sender", state: .ready)
        let sender = manifest(host, "sender")
        #expect(host.actionables.apply(Move(to: .done), transition: "merge", to: note.id, by: "sender", manifest: sender, trigger: "t")
            == .failure(.failed("sender has no transition merge")))
        let working = host.seed(kind: "note", owner: "sender", state: .working)
        #expect(host.actionables.apply(Move(to: .working), transition: "start", to: working.id, by: "sender", manifest: sender, trigger: "t")
            == .failure(.failed("start does not start from working")))
        #expect(host.actionables.apply(Move(to: .done), transition: "send", to: working.id, by: "sender", manifest: sender, trigger: "t")
            == .failure(.failed("send is outward, so it needs actionables.request")))
    }

    @Test func aMoveWithDataThatDoesNotFitTheKindIsRefused() {
        let host = PluginHost.actionables()
        let bug = host.seed(kind: "bug", owner: "asker", state: .new, data: .object(["repo": .string("demo"), "details": .string("x")]))
        let moved = host.actionables.apply(
            Move(to: .dropped, data: .object(["repo": .string("demo")])), transition: "drop", to: bug.id, by: "asker", manifest: manifest(host, "asker"),
            trigger: "t", handles: host.handles)
        #expect(moved == .failure(.failed("data.details is required")))
        #expect(host.actionables.actionable(bug.id)?.state == .new)
    }

    @Test func aHandoffChangesTheOwnerInOneStep() throws {
        let host = PluginHost.actionables()
        let note = host.seed(kind: "note", owner: "sender", state: .working)
        let moved = try host.actionables.handoff(Handoff(state: .new, kind: "bug", data: bugData), of: note.id, by: "sender", handles: host.handles, trigger: "t").get()
        #expect(moved.owner == "asker" && moved.pastOwners == ["sender"] && moved.kind == "bug" && moved.state == .new)
        #expect(moved.steps.count == 2)
        #expect(moved.steps.last?.action == .handoff && moved.steps.last?.oldOwner == "sender" && moved.steps.last?.oldKind == "note")
        #expect(moved.id == note.id)
    }

    @Test func aHandoffWithDataThatDoesNotFitIsRefused() {
        let host = PluginHost.actionables()
        let note = host.seed(kind: "note", owner: "sender", state: .working)
        let moved = host.actionables.handoff(Handoff(state: .new, kind: "bug", data: .object(["repo": .string("demo")])), of: note.id, by: "sender", handles: host.handles, trigger: "t")
        #expect(moved == .failure(.failed("data.details is required")))
        #expect(host.actionables.actionable(note.id)?.owner == "sender")
    }

    @Test func aHandoffThatNoRoutineHandlesIsRefusedAndTheOwnerStays() {
        let host = PluginHost.actionables()
        let note = host.seed(kind: "note", owner: "sender", state: .working)
        #expect(host.actionables.handoff(Handoff(state: .done, kind: "bug", data: bugData), of: note.id, by: "sender", handles: host.handles, trigger: "t")
            == .failure(.failed("no routine handles bug in done")))
        #expect(host.actionables.handoff(Handoff(state: .ready), of: note.id, by: "sender", handles: host.handles, trigger: "t")
            == .failure(.failed("sender cannot hand an actionable to itself")))
        #expect(host.actionables.actionable(note.id)?.owner == "sender")
        #expect(host.actionables.actionable(note.id)?.steps.count == 1)
    }

    @Test func aRunOfTheSenderHandsItsNoteToTheAsker() async throws {
        let host = PluginHost.actionables()
        let note = host.seed(kind: "note", owner: "sender", state: .ready)
        _ = try await host.answer(of: .transition("start", of: note.id, routine: "sender", source: .ui, at: host.now())).get()
        #expect(host.actionables.actionable(note.id)?.state == .working)
        host.submit(.run("sender", source: .clock, at: host.now()))
        await waitUntil { host.actionables.actionable(note.id)?.owner == "asker" && host.running.isEmpty }
        let moved = try #require(host.actionables.actionable(note.id))
        #expect(moved.kind == "bug" && moved.state == .waitingOnYou)
        #expect(moved.steps.map(\.action.description) == ["created", "transition:start", "handoff", "transition:ask"])
    }
}

@MainActor
struct MigrationTests {
    @Test func boardFilesBecomeActionablesOnce() throws {
        let paths = Fixture.actionablePaths()
        let board = paths.file("board")
        try FileManager.default.createDirectory(at: board, withIntermediateDirectories: true)
        let mail = #"[{"id":"m1","title":"Reply","column":"needs-you","actions":[{"id":"done","label":"Done"}],"updatedAt":"2026-11-01T10:00:00Z"},{"id":"m2","title":"Done one","column":"done"}]"#
        try Data(mail.utf8).write(to: board.appendingPathComponent("mail.json"))
        try Data(#"[{"id":"j1","title":"Job","column":"planned","data":{"score":3}}]"#.utf8).write(to: board.appendingPathComponent("jobs.json"))

        let store = ActionableStore(dir: paths.file("actionables"))
        Migration.run(boardDir: board, store: store)
        let reply = try #require(store.find(source: "mail", key: "m1"))
        #expect(reply.owner == "mail" && reply.kind == "mail" && reply.state == .waitingOnYou)
        #expect(reply.steps.map(\.action) == [.migrated])
        #expect(reply.updatedAt == ISO8601.parse("2026-11-01T10:00:00Z"))
        #expect(store.find(source: "mail", key: "m2")?.state == .done)
        #expect(store.find(source: "jobs", key: "j1")?.state == .ready)
        #expect(store.find(source: "jobs", key: "j1")?.data == .object(["score": .number(3)]))
        let files = try FileManager.default.contentsOfDirectory(atPath: board.path).sorted()
        #expect(files == ["jobs.json.migrated", "mail.json.migrated"])

        Migration.run(boardDir: board, store: store)
        #expect(store.all.count == 3)
        #expect(ActionableStore(dir: paths.file("actionables")).all.count == 3)
    }

    @Test func aBoardFileThatDoesNotParseStays() throws {
        let paths = Fixture.actionablePaths()
        let board = paths.file("board")
        try FileManager.default.createDirectory(at: board, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: board.appendingPathComponent("mail.json"))
        let store = ActionableStore(dir: paths.file("actionables"))
        Migration.run(boardDir: board, store: store)
        #expect(store.all.isEmpty)
        #expect(FileManager.default.fileExists(atPath: board.appendingPathComponent("mail.json").path))
    }
}
