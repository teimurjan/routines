import Foundation

/// Why the host refused a request. Each caller gets the same text (FR-015). See specs/004-actionables/contracts/entrance.md.
public enum Refusal: Error, Equatable, Sendable, CustomStringConvertible {
    case noRoutine(String)
    case blocked(String)
    case noActionable(String)
    case notOwner(routine: String, actionable: String)
    case noTransition(routine: String, transition: String)
    case wrongState(transition: String, state: Actionable.State)
    case needsText(label: String)
    case notExternal(routine: String, transition: String)
    case needsPress(label: String)
    case notWaiting(actionable: String)
    case staleQuestion
    case noAction(routine: String, action: String)
    case needsItem(action: String)
    case needsRequest(transition: String, risk: Risk)
    case sourceCannotMove
    case noHandler(kind: String, state: Actionable.State)
    case sameRoutine(String)
    case badData(String)
    case badQuestion(String)

    public var description: String {
        switch self {
        case .noRoutine(let id): "the routine \(id) does not exist"
        case .blocked(let reason): reason
        case .noActionable(let id): "there is no actionable \(id)"
        case .notOwner(let routine, let actionable): "\(routine) does not own actionable \(actionable)"
        case .noTransition(let routine, let transition): "\(routine) has no transition \(transition)"
        case .wrongState(let transition, let state): "\(transition) does not start from \(state.rawValue)"
        case .needsText(let label): "the transition \(label) needs text"
        case .notExternal(let routine, let transition): "\(routine) does not allow \(transition) from outside the app"
        case .needsPress(let label): "\(label) starts only from a press in the app"
        case .notWaiting(let id): "actionable \(id) no longer waits on you"
        case .staleQuestion: "this question was already answered"
        case .noAction(let routine, let action): "\(routine) has no action \(action)"
        case .needsItem(let action): "\(action) needs an item"
        case .needsRequest(let transition, let risk): "\(transition) is \(risk.rawValue), so it needs actionables.request"
        case .sourceCannotMove: "a source cannot move an actionable"
        case .noHandler(let kind, let state): "no routine handles \(kind) in \(state.rawValue)"
        case .sameRoutine(let routine): "\(routine) cannot hand an actionable to itself"
        case .badData(let reason): reason
        case .badQuestion(let reason): reason
        }
    }

    public var error: HostError { .failed(description) }
}

/// What the host does with one trigger. See "Decision" in specs/004-actionables/data-model.md.
public enum Decision: Equatable, Sendable {
    case startRun
    case queueRun
    case merge
    case callTransition
    case callAction
    /// Ask you before this transition.
    case ask(String)
    case refuse(Refusal)

    public var name: String {
        switch self {
        case .startRun: "startRun"
        case .queueRun: "queueRun"
        case .merge: "merge"
        case .callTransition: "callTransition"
        case .callAction: "callAction"
        case .ask: "ask"
        case .refuse: "refuse"
        }
    }

    public var refusal: Refusal? {
        if case .refuse(let refusal) = self { return refusal }
        return nil
    }
}

/// The one pure decision of each trigger. Its world holds no memory, so no memory entry can change a decision (R8).
public enum Policy {
    public struct World: Sendable {
        public var manifests: [String: Manifest]
        public var handles: HandlesTable
        /// Why each routine cannot run now.
        public var blockers: [String: String]
        /// The stored actionable that the trigger names.
        public var actionable: Actionable?
        /// The `outward` and `destructive` transitions that you allow this routine.
        public var allowList: Set<String>
        public var lifecycle: RunLifecycle

        public init(
            manifests: [String: Manifest], handles: HandlesTable, blockers: [String: String], actionable: Actionable?, allowList: Set<String>,
            lifecycle: RunLifecycle
        ) {
            self.manifests = manifests
            self.handles = handles
            self.blockers = blockers
            self.actionable = actionable
            self.allowList = allowList
            self.lifecycle = lifecycle
        }
    }

    public static func decide(_ trigger: Trigger, _ world: World) -> Decision {
        switch check(trigger, world) {
        case .success(let decision): decision
        case .failure(let refusal): .refuse(refusal)
        }
    }

    private static func check(_ trigger: Trigger, _ world: World) -> Result<Decision, Refusal> {
        guard let manifest = world.manifests[trigger.routine] else { return .failure(.noRoutine(trigger.routine)) }
        if let blocker = world.blockers[trigger.routine] { return .failure(.blocked(blocker)) }
        switch trigger.work {
        case .run: return .success(run(world.lifecycle))
        case .action: return action(trigger, manifest: manifest)
        case .transition: return transition(trigger, manifest: manifest, world: world)
        }
    }

    private static func run(_ lifecycle: RunLifecycle) -> Decision {
        switch lifecycle {
        case .idle: .startRun
        case .running: .queueRun
        case .queued: .merge
        }
    }

    private static func action(_ trigger: Trigger, manifest: Manifest) -> Result<Decision, Refusal> {
        let id = trigger.transition ?? ""
        guard let action = manifest.actions.first(where: { $0.id == id }) else { return .failure(.noAction(routine: manifest.id, action: id)) }
        if action.isItemAction { return .failure(.needsItem(action: id)) }
        if action.input != nil, isBlank(trigger.text) { return .failure(.needsText(label: action.label)) }
        if action.needsConfirmation, trigger.source != .ui { return .failure(.needsPress(label: action.label)) }
        if trigger.source == .external, !manifest.permissions.external.contains(id) { return .failure(.notExternal(routine: manifest.id, transition: id)) }
        return .success(.callAction)
    }

    private static func transition(_ trigger: Trigger, manifest: Manifest, world: World) -> Result<Decision, Refusal> {
        let routine = manifest.id
        let id = trigger.transition ?? ""
        // Check 2: the actionable exists, and the routine owns it.
        guard let actionable = world.actionable, actionable.id == trigger.actionable else { return .failure(.noActionable(trigger.actionable ?? "")) }
        guard actionable.owner == routine else { return .failure(.notOwner(routine: routine, actionable: actionable.id)) }
        // Check 7 comes first for an answer, so a late answer names the question and not the state.
        let asked = trigger.grant == nil ? nil : actionable.steps.last
        if trigger.source == .answer {
            guard actionable.state == .waitingOnYou else { return .failure(.notWaiting(actionable: actionable.id)) }
            guard let last = actionable.steps.last, last.id == trigger.answers, last.question != nil else { return .failure(.staleQuestion) }
        }
        // Check 3: the transition, from the state before a permission question.
        guard let declaration = manifest.transition(id) else { return .failure(.noTransition(routine: routine, transition: id)) }
        let state = asked?.from ?? actionable.state
        guard declaration.from.contains(state) else { return .failure(.wrongState(transition: id, state: state)) }
        // Check 4: the text of the request, which a permission question keeps.
        if declaration.input != nil, isBlank(trigger.text ?? asked?.question?.input) { return .failure(.needsText(label: declaration.label)) }
        // Checks 5 and 6: the sources that FR-025 and FR-027 name. A press comes first, so a script learns that only a press starts it.
        if declaration.needsConfirmation, trigger.source != .ui { return .failure(.needsPress(label: declaration.label)) }
        if trigger.source == .external, !manifest.permissions.external.contains(id) { return .failure(.notExternal(routine: routine, transition: id)) }
        // Check 8: a press and an answer are your consent. Each other source needs the allow list.
        if declaration.risk.needsConsent, trigger.source != .ui, trigger.source != .answer, !world.allowList.contains(id) { return .success(.ask(id)) }
        return .success(.callTransition)
    }

    static func isBlank(_ text: String?) -> Bool {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
