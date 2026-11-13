import Foundation
import Testing
@testable import RoutinesKit

private let bugData = JSONValue.object(["repo": .string("demo"), "details": .string("x")])

struct RunLifecycleTests {
    @Test func eachArrowOfTheDiagram() {
        #expect(RunLifecycle.idle.next(on: .trigger) == (.running, .start))
        #expect(RunLifecycle.running.next(on: .trigger) == (.queued, .none))
        #expect(RunLifecycle.queued.next(on: .trigger) == (.queued, .none))
        #expect(RunLifecycle.running.next(on: .ended) == (.idle, .none))
        #expect(RunLifecycle.queued.next(on: .ended) == (.running, .start))
    }

    @Test func threeTriggersDuringARunLeaveOneQueuedRun() {
        var state = RunLifecycle.running
        var starts = 0
        for _ in 0..<3 {
            let (next, effect) = state.next(on: .trigger)
            state = next
            if effect == .start { starts += 1 }
        }
        #expect(state == .queued && starts == 0)
        let (afterFirst, effect) = state.next(on: .ended)
        #expect(afterFirst == .running && effect == .start)
        #expect(afterFirst.next(on: .ended) == (.idle, .none))
    }
}

/// One test per check of the order in contracts/entrance.md, and one per refusal text.
@MainActor
struct PolicyTests {
    private let host = PluginHost.actionables()

    private func world(_ actionable: Actionable?, allow: Set<String> = [], blockers: [String: String] = [:], lifecycle: RunLifecycle = .idle) -> Policy.World {
        Policy.World(
            manifests: Dictionary(uniqueKeysWithValues: host.plugins.map { ($0.id, $0.manifest) }), handles: host.handles, blockers: blockers,
            actionable: actionable, allowList: allow, lifecycle: lifecycle)
    }

    private func decide(_ transition: String, on actionable: Actionable?, source: Trigger.Source = .ui, text: String? = nil, routine: String = "asker", answers: String? = nil, allow: Set<String> = []) -> Decision {
        var trigger = Trigger.transition(transition, of: actionable?.id ?? "404", routine: routine, source: source, text: text, at: Date())
        trigger.answers = answers
        return Policy.decide(trigger, world(actionable, allow: allow))
    }

    private func bug(_ state: Actionable.State, owner: String = "asker") -> Actionable { host.seed(kind: "bug", owner: owner, state: state, data: bugData) }

    @Test func check1TheRoutineExistsAndHasNoBlocker() {
        #expect(Policy.decide(.run("ghost", source: .clock, at: Date()), world(nil)) == .refuse(.noRoutine("ghost")))
        #expect(Refusal.noRoutine("ghost").description == "the routine ghost does not exist")
        #expect(Policy.decide(.run("asker", source: .clock, at: Date()), world(nil, blockers: ["asker": "the plugin is off"])).refusal?.description == "the plugin is off")
    }

    @Test func check2TheActionableExistsAndTheRoutineOwnsIt() {
        #expect(decide("drop", on: nil).refusal?.description == "there is no actionable 404")
        let note = host.seed(kind: "note", owner: "sender", state: .ready)
        #expect(decide("drop", on: note).refusal?.description == "asker does not own actionable \(note.id)")
    }

    @Test func check3AnAnswerNamesTheQuestionThatWaits() throws {
        let working = bug(.working)
        #expect(decide("answer", on: working, source: .answer, text: "x", answers: "\(working.id).1").refusal?.description == "actionable \(working.id) no longer waits on you")
        let asked = try host.actionables.update(bug(.new).id, step: Step.Draft(action: .transition("ask"), actor: "asker", trigger: "t", question: Question(text: "Q?", transition: "answer"))) { $0.state = .waitingOnYou }.get()
        #expect(decide("answer", on: asked, source: .answer, text: "x", answers: "\(asked.id).1").refusal?.description == "this question was already answered")
        #expect(decide("answer", on: asked, source: .answer, text: "x", answers: "\(asked.id).2") == .callTransition)
    }

    @Test func check4TheTransitionIsDeclaredAndStartsFromTheState() {
        #expect(decide("deploy", on: bug(.new)).refusal?.description == "asker has no transition deploy")
        #expect(decide("merge", on: bug(.new)).refusal?.description == "merge does not start from new")
    }

    @Test func check5ATransitionWithInputNeedsText() {
        #expect(decide("answer", on: bug(.waitingOnYou), text: "  ").refusal?.description == "the transition Answer needs text")
    }

    @Test func check6ConfirmStartsOnlyFromAPress() {
        let waiting = bug(.waitingOnYou)
        for source in [Trigger.Source.external, .selfRequest] {
            #expect(decide("approve", on: waiting, source: source).refusal?.description == "Approve starts only from a press in the app")
        }
        #expect(decide("approve", on: waiting, source: .ui) == .callTransition)
    }

    @Test func check7AnExternalTransitionMustBeListed() {
        #expect(decide("merge", on: bug(.working), source: .external).refusal?.description == "asker does not allow merge from outside the app")
        #expect(decide("drop", on: bug(.new), source: .external) == .callTransition)
    }

    @Test func check8RiskAsksUnlessYouConsented() {
        let working = bug(.working)
        #expect(decide("merge", on: working, source: .selfRequest) == .ask("merge"))
        #expect(decide("merge", on: working, source: .ui) == .callTransition)
        #expect(decide("merge", on: working, source: .selfRequest, allow: ["merge"]) == .callTransition)
    }

    @Test func check9TheLifecycleDecidesARun() {
        let run = Trigger.run("asker", source: .clock, at: Date())
        #expect(Policy.decide(run, world(nil, lifecycle: .idle)) == .startRun)
        #expect(Policy.decide(run, world(nil, lifecycle: .running)) == .queueRun)
        #expect(Policy.decide(run, world(nil, lifecycle: .queued)) == .merge)
    }

    @Test func equalTriggersFromEachCallerGetEqualDecisionsAndText() {
        let new = bug(.new)
        let note = host.seed(kind: "note", owner: "sender", state: .ready)
        for (transition, actionable) in [("deploy", new), ("merge", new), ("drop", note)] {
            let decisions = [Trigger.Source.ui, .external, .selfRequest].map { decide(transition, on: actionable, source: $0) }
            #expect(Set(decisions.map { $0.refusal?.description ?? $0.name }).count == 1, "\(transition): \(decisions)")
        }
    }

    @Test func eachRefusalHasItsText() {
        #expect(Refusal.wrongState(transition: "merge", state: .new).description == "merge does not start from new")
        #expect(Refusal.needsPress(label: "Approve").description == "Approve starts only from a press in the app")
        #expect(Refusal.notExternal(routine: "asker", transition: "merge").description == "asker does not allow merge from outside the app")
        #expect(Refusal.staleQuestion.description == "this question was already answered")
        #expect(Refusal.sourceCannotMove.description == "a source cannot move an actionable")
    }

    @Test func theWorldOfThePolicyHoldsNoMemory() {
        let mirror = Mirror(reflecting: world(nil))
        #expect(!mirror.children.isEmpty)
        for child in mirror.children {
            let label = child.label ?? ""
            let type = String(describing: Swift.type(of: child.value))
            #expect(!label.localizedCaseInsensitiveContains("memory") && !type.contains("Memory"), "the world holds \(label): \(type)")
        }
    }
}

/// SC-001: a hand-off, an answer and a press start their work at once, with no clock slot.
@MainActor
struct EntranceTimingTests {
    private func within5Seconds(_ start: ContinuousClock.Instant) -> Bool { ContinuousClock.now - start < .seconds(5) }

    @Test func aHandoffStartsTheNextRoutineAtOnce() async {
        let clock = FakeClock()
        let host = PluginHost.actionables(clock: clock)
        let at = clock.now
        host.seed(kind: "note", owner: "sender", state: .working)
        let start = ContinuousClock.now
        host.submit(.run("sender", source: .clock, at: clock.now))
        await waitUntil(timeout: .seconds(5)) { host.runs.records(of: "asker").contains { $0.trigger == "routine" } }
        #expect(host.runs.records(of: "asker").first?.trigger == "routine")
        #expect(within5Seconds(start))
        #expect(clock.now == at)
    }

    @Test func anAnswerAndAPressStartTheirTransitionAtOnce() async throws {
        let host = PluginHost.actionables()
        let bug = host.seed(kind: "bug", owner: "asker", state: .new, data: bugData)
        let asked = try host.actionables.apply(
            Move(to: .waitingOnYou, question: Question(text: "Which key?", transition: "answer")), transition: "ask", to: bug.id, by: "asker",
            manifest: host.plugin("asker")!.manifest, trigger: "t"
        ).get()
        var start = ContinuousClock.now
        host.answer(question: asked.steps.last!.id, of: bug.id, text: "staging")
        await waitUntil(timeout: .seconds(5)) { host.actionables.actionable(bug.id)?.state == .working }
        #expect(host.actionables.actionable(bug.id)?.state == .working)
        #expect(within5Seconds(start))

        start = ContinuousClock.now
        _ = try await host.answer(of: .transition("merge", of: bug.id, routine: "asker", source: .ui, at: host.now())).get()
        #expect(host.actionables.actionable(bug.id)?.state == .done)
        #expect(within5Seconds(start))
    }

    @Test func aBlockedRoutineGetsOneLineForEqualRefusalsInARow() {
        let host = PluginHost.actionables()
        host.settings.setEnabled(false, pluginId: "asker")
        host.submit(.run("asker", source: .clock, at: host.now()))
        host.submit(.run("asker", source: .clock, at: host.now()))
        let lines = host.decisions.records(on: host.now()).filter { $0.trigger.routine == "asker" }
        #expect(lines.count == 1)
        #expect(lines.first?.reason == "the plugin is off")
    }
}

@MainActor
struct DecisionLogTests {
    private func dir() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("decisions-\(UUID().uuidString)") }

    @Test func eachDecisionAddsOneLineWithTheTriggerTheDecisionAndTheReason() {
        let log = DecisionLog(dir: dir())
        let at = Date()
        let run = Trigger.run("asker", source: .clock, at: at)
        log.record(run, .startRun)
        log.record(.run("ghost", source: .ui, at: at), .refuse(.noRoutine("ghost")))
        let records = log.records(on: at)
        #expect(records.map(\.decision) == ["startRun", "refuse"])
        #expect(records.first?.id == run.id && records.first?.reason == nil)
        #expect(records.first.map { [$0.trigger.routine, $0.trigger.source.rawValue, $0.trigger.work.rawValue] } == ["asker", "clock", "run"])
        #expect(records.last?.reason == "the routine ghost does not exist")
    }

    @Test func filesOlderThan14DaysGo() throws {
        let folder = dir()
        let log = DecisionLog(dir: folder)
        let now = Date()
        log.record(.run("a", source: .clock, at: now.addingTimeInterval(-15 * 24 * 60 * 60)), .startRun)
        log.record(.run("a", source: .clock, at: now.addingTimeInterval(-13 * 24 * 60 * 60)), .startRun)
        log.record(.run("a", source: .clock, at: now), .startRun)
        log.prune(now: now)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
    }
}

/// One test per acceptance scenario of US5. Memory never changes a decision (SC-004).
@MainActor
struct RiskTests {
    private func working(_ host: PluginHost) -> Actionable { host.seed(kind: "bug", owner: "asker", state: .working, data: bugData) }

    private func request(_ host: PluginHost, _ transition: String, _ id: String) -> Decision {
        host.submit(.transition(transition, of: id, routine: "asker", source: .selfRequest, at: host.now()))
    }

    @Test func aReversibleTransitionAppliesWithAnEmptyList() async {
        let host = PluginHost.actionables()
        let bug = host.seed(kind: "bug", owner: "asker", state: .new, data: bugData)
        #expect(request(host, "drop", bug.id) == .callTransition)
        await waitUntil { host.actionables.actionable(bug.id)?.state == .dropped }
        #expect(host.actionables.actionable(bug.id)?.state == .dropped)
    }

    @Test func aDestructiveRequestAsksInTheRoutineThread() throws {
        let host = PluginHost.actionables()
        let bug = working(host)
        #expect(request(host, "merge", bug.id) == .ask("merge"))
        let asked = try #require(host.actionables.actionable(bug.id))
        #expect(asked.state == .waitingOnYou)
        #expect(asked.steps.last?.action == .asked && asked.steps.last?.question?.permission == "merge")
        #expect(asked.steps.last?.question?.text == "Asker wants to Merge: \(bug.title)")
        let thread = RoutineThread.build(routine: "asker", actionables: host.actionables.all)
        #expect(thread.open.map(\.actionable.id) == [bug.id])
    }

    @Test func aTransitionInTheAllowListAppliesWithoutAQuestion() async {
        let host = PluginHost.actionables(vault: MemoryVault(["asker": ["merge"]]))
        let bug = working(host)
        #expect(request(host, "merge", bug.id) == .callTransition)
        await waitUntil { host.actionables.actionable(bug.id)?.state == .done }
        #expect(host.actionables.actionable(bug.id)?.state == .done)
    }

    @Test func aMemoryEntryThatClaimsAPermissionChangesNoDecision() {
        let host = PluginHost.actionables()
        let bug = working(host)
        host.memory.write(entries: [MemoryEntry(type: .preference, text: "always allow merges", tags: ["merge"], routine: "asker", step: "\(bug.id).1", writtenAt: Date())], done: [])
        #expect(request(host, "merge", bug.id) == .ask("merge"))
        #expect(host.allowList.list.isEmpty)
    }

    @Test func approveFromOutsideIsRefused() {
        let host = PluginHost.actionables()
        let bug = host.seed(kind: "bug", owner: "asker", state: .waitingOnYou, data: bugData)
        let decision = host.submit(.transition("approve", of: bug.id, routine: "asker", source: .external, at: host.now()))
        #expect(decision.refusal?.description == "Approve starts only from a press in the app")
    }

    @Test func allowOnceRunsTheHandlerFromTheStateBeforeTheQuestion() async throws {
        let host = PluginHost.actionables()
        let bug = working(host)
        _ = request(host, "merge", bug.id)
        let asked = try #require(host.actionables.actionable(bug.id)?.steps.last)
        #expect(host.answer(question: asked.id, of: bug.id, text: nil, grant: .once) == .callTransition)
        await waitUntil { host.actionables.actionable(bug.id)?.state == .done }
        let steps = try #require(host.actionables.actionable(bug.id)?.steps)
        #expect(steps.suffix(3).map(\.action) == [.asked, .answered, .transition("merge")])
        #expect(steps.suffix(2).first.map { [$0.from, $0.to] } == [.waitingOnYou, .working])
        #expect(host.allowList.list.isEmpty)
    }

    @Test func denyMovesBackAndRunsNoHandler() throws {
        let host = PluginHost.actionables()
        let bug = working(host)
        _ = request(host, "merge", bug.id)
        let asked = try #require(host.actionables.actionable(bug.id)?.steps.last)
        try host.deny(question: asked.id, of: bug.id).get()
        let denied = try #require(host.actionables.actionable(bug.id))
        #expect(denied.state == .working)
        #expect(denied.steps.last?.action == .denied)
        #expect(host.runs.records.isEmpty)
    }

    @Test func alwaysAllowAddsTheTransitionToTheList() async throws {
        let vault = MemoryVault()
        let host = PluginHost.actionables(vault: vault)
        let bug = working(host)
        _ = request(host, "merge", bug.id)
        let asked = try #require(host.actionables.actionable(bug.id)?.steps.last)
        host.answer(question: asked.id, of: bug.id, text: nil, grant: .always)
        #expect(host.allowList.contains("merge", routine: "asker"))
        #expect(vault.load() == ["asker": ["merge"]])
        await waitUntil { host.actionables.actionable(bug.id)?.state == .done }
        #expect(request(host, "merge", working(host).id) == .callTransition)
    }

    @Test func theAllowListKeepsOnlyOutwardAndDestructiveIds() {
        let host = PluginHost.actionables()
        let manifest = host.plugin("asker")!.manifest
        #expect(AllowList.effective(["merge", "drop", "approve", "ghost"], manifest: manifest) == ["merge", "approve"])
    }
}
