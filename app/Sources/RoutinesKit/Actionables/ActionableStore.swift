import Foundation
import Observation

/// Each actionable in one JSON file, so each change is one atomic write (R5). See specs/004-actionables/research.md, section 1.
@MainActor
@Observable
public final class ActionableStore {
    public private(set) var actionables: [String: Actionable] = [:]
    /// Files that did not parse, by actionable id. The store never writes over them.
    public private(set) var errors: [String: String] = [:]
    @ObservationIgnored private var byOwner: [String: Set<String>] = [:]
    @ObservationIgnored private var byKey: [Key: String] = [:]
    @ObservationIgnored private let dir: URL
    @ObservationIgnored private let now: @Sendable () -> Date
    /// The days that an owner keeps its closed actionables. 0 keeps them. Nil is for no owner.
    @ObservationIgnored public var retentionDays: @MainActor (String?) -> Int = { _ in DoneCards.defaultRetentionDays }
    /// Called after each stored step, for example to post the notification of a question.
    @ObservationIgnored public var onStep: @MainActor (Actionable, Step) -> Void = { _, _ in }

    nonisolated public static let dataLimit = 32 * 1024
    nonisolated static let titleLimit = 200

    private struct Key: Hashable {
        var source: String
        var dedupeKey: String
    }

    public init(dir: URL, now: @escaping @Sendable () -> Date = Date.init) {
        self.dir = dir
        self.now = now
        load()
    }

    private func file(_ id: String) -> JSONFile<Actionable> {
        JSONFile(url: dir.appendingPathComponent("\(id).json"))
    }

    private var nextIdFile: JSONFile<String> { JSONFile(url: dir.appendingPathComponent("next-id.json")) }

    private func load() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names where name.hasSuffix(".json") && name != "next-id.json" {
            let id = String(name.dropLast(5))
            switch file(id).load(default: Actionable.placeholder) {
            case .success(let actionable): index(actionable)
            case .failure(let error): errors[id] = error.description
            }
        }
    }

    // MARK: Reads

    public func actionable(_ id: String) -> Actionable? {
        actionables[id]
    }

    /// The actionables that a routine owns now, newest change first.
    public func owned(by routine: String) -> [Actionable] {
        sorted((byOwner[routine] ?? []).compactMap { actionables[$0] })
    }

    /// The actionables that a routine owned before and does not own now.
    public func past(of routine: String) -> [Actionable] {
        sorted(actionables.values.filter { $0.owner != routine && $0.pastOwners.contains(routine) })
    }

    public func unowned() -> [Actionable] {
        sorted(actionables.values.filter { $0.owner == nil })
    }

    public func find(source: String, key: String) -> Actionable? {
        byKey[Key(source: source, dedupeKey: key)].flatMap { actionables[$0] }
    }

    public var all: [Actionable] { sorted(Array(actionables.values)) }

    /// The steps that one decision made, in order.
    public func steps(trigger: String) -> [(actionable: Actionable, step: Step)] {
        actionables.values.flatMap { actionable in actionable.steps.filter { $0.trigger == trigger }.map { (actionable, $0) } }
            .sorted { $0.step.at < $1.step.at }
    }

    private func sorted(_ list: [Actionable]) -> [Actionable] {
        list.sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
    }

    // MARK: Writes

    /// A new actionable with its first step. A second actionable with the same source and dedupe key is refused (FR-022).
    public func create(
        kind: String, source: String, dedupeKey: String, owner: String?, state: Actionable.State, title: String, step: Step.Draft,
        fill: (inout Actionable) -> Void = { _ in }
    ) -> Result<Actionable, HostError> {
        if find(source: source, key: dedupeKey) != nil { return .failure(.failed("\(source) already has an actionable with the key \(dedupeKey)")) }
        guard case .success(let id) = takeId() else { return .failure(.failed("actionables/next-id.json does not parse")) }
        let at = now()
        var actionable = Actionable(
            id: id, kind: kind, source: source, dedupeKey: dedupeKey, owner: owner, state: state, title: title, createdAt: at, updatedAt: at)
        fill(&actionable)
        actionable.steps = [Step(id: "\(id).1", at: at, draft: step, from: state, to: actionable.state)]
        return announced(save(actionable))
    }

    /// Changes one actionable. A draft adds one step from the state before the change to the state after it. A nil draft changes only display fields.
    @discardableResult
    public func update(_ id: String, step: Step.Draft?, changes: (inout Actionable) -> Void) -> Result<Actionable, HostError> {
        if let error = errors[id] { return .failure(.failed(error)) }
        guard let current = actionables[id] else { return .failure(.failed("there is no actionable \(id)")) }
        var changed = current
        changes(&changed)
        changed.id = current.id
        changed.steps = current.steps
        changed.updatedAt = now()
        if let step {
            changed.steps.append(Step(id: "\(id).\(current.steps.count + 1)", at: changed.updatedAt, draft: step, from: current.state, to: changed.state))
        } else if changed.state != current.state {
            return .failure(.failed("a change of state needs a step"))
        }
        let saved = save(changed)
        return step == nil ? saved : announced(saved)
    }

    private func announced(_ saved: Result<Actionable, HostError>) -> Result<Actionable, HostError> {
        if case .success(let actionable) = saved, let step = actionable.steps.last { onStep(actionable, step) }
        return saved
    }

    /// Shows a line on the actionable without a step, for example while an action runs.
    public func setStatus(_ status: String?, of id: String) {
        update(id, step: nil) { $0.status = status }
    }

    /// Deletes the closed actionables that passed the retention of their owner.
    public func prune() {
        let at = now()
        for actionable in actionables.values where actionable.state.isClosed {
            let days = retentionDays(actionable.owner)
            guard days > 0, at.timeIntervalSince(actionable.updatedAt) >= Double(days) * 24 * 60 * 60 else { continue }
            guard (try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(actionable.id).json"))) != nil else { continue }
            unindex(actionable)
            actionables[actionable.id] = nil
        }
    }

    private func save(_ actionable: Actionable) -> Result<Actionable, HostError> {
        if let problem = Self.check(actionable) { return .failure(.failed(problem)) }
        return file(actionable.id).save(actionable).map {
            if let old = actionables[actionable.id] { unindex(old) }
            index(actionable)
            return actionable
        }
    }

    static func check(_ actionable: Actionable) -> String? {
        if actionable.title.isEmpty || actionable.title.count > titleLimit { return "the title of actionable \(actionable.id) must have 1 to \(titleLimit) characters" }
        guard case .object = actionable.data else { return "the data of actionable \(actionable.id) must be an object" }
        let size = (try? JSONEncoder().encode(actionable.data))?.count ?? 0
        if size > dataLimit { return "the data of actionable \(actionable.id) is \(size) bytes as JSON. At most 32 KB as JSON is allowed." }
        if let link = actionable.links.first(where: { !Self.isWebLink($0.url) }) { return "the link \(link.url) is not http or https" }
        return nil
    }

    private static func isWebLink(_ text: String) -> Bool {
        guard let scheme = URL(string: text)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// The next id. A file that does not parse stops each create, so ids never repeat.
    private func takeId() -> Result<String, HostError> {
        let known = (actionables.keys.compactMap(Int.init) + errors.keys.compactMap(Int.init)).max() ?? 0
        return nextIdFile.load(default: "1").flatMap { text in
            let id = max(Int(text) ?? 1, known + 1)
            return nextIdFile.save(String(id + 1)).map { String(id) }
        }
    }

    private func index(_ actionable: Actionable) {
        actionables[actionable.id] = actionable
        if let owner = actionable.owner { byOwner[owner, default: []].insert(actionable.id) }
        byKey[Key(source: actionable.source, dedupeKey: actionable.dedupeKey)] = actionable.id
    }

    private func unindex(_ actionable: Actionable) {
        if let owner = actionable.owner { byOwner[owner]?.remove(actionable.id) }
        byKey[Key(source: actionable.source, dedupeKey: actionable.dedupeKey)] = nil
    }
}

extension Actionable {
    /// Only the default of a load. A missing file never reaches the store, because the store reads the names in its folder.
    static let placeholder = Actionable(
        id: "", kind: "", source: "", dedupeKey: "", owner: nil, state: .new, title: "", createdAt: .distantPast, updatedAt: .distantPast)
}

extension ActionableStore {
    public enum MoveKind: Sendable {
        /// A move in a run, which the routine asks for itself.
        case run
        /// The move that a transition handler returned, after the policy allowed its trigger.
        case handled
    }

    /// Checks a move, and its data against the kind, and appends exactly one step with the action `transition:<id>`.
    public func apply(
        _ move: Move, transition id: String, to actionableId: String, by routine: String, manifest: Manifest, trigger: String, kind: MoveKind = .run,
        handles: HandlesTable = .empty
    ) -> Result<Actionable, HostError> {
        guard let actionable = actionable(actionableId) else { return .failure(Refusal.noActionable(actionableId).error) }
        let checked = kind == .run
            ? MoveCheck.move(move, transition: id, by: routine, actionable: actionable, manifest: manifest)
            : MoveCheck.handled(move, routine: routine, manifest: manifest)
        switch checked {
        case .failure(let refusal): return .failure(refusal.error)
        case .success(let move):
            if let data = move.data, case .failure(let error) = handles.schema(of: actionable.kind).validate(data) { return .failure(error) }
            let step = Step.Draft(action: .transition(id), actor: routine, trigger: trigger, outcome: move.status, question: move.question)
            return update(actionableId, step: step) { $0.apply(move) }
        }
    }

    /// Checks a hand-off and changes the owner in one `handoff` step (FR-007).
    public func handoff(_ change: Handoff, of actionableId: String, by routine: String, handles: HandlesTable, trigger: String) -> Result<Actionable, HostError> {
        guard let actionable = actionable(actionableId) else { return .failure(Refusal.noActionable(actionableId).error) }
        switch MoveCheck.handoff(change, by: routine, actionable: actionable, handles: handles) {
        case .failure(let refusal): return .failure(refusal.error)
        case .success(let handler):
            let step = Step.Draft(action: .handoff, actor: routine, trigger: trigger, oldOwner: routine, oldKind: actionable.kind)
            return update(actionableId, step: step) { moved in
                moved.pastOwners.append(routine)
                moved.owner = handler
                moved.state = change.state
                moved.kind = change.kind ?? moved.kind
                moved.title = change.title ?? moved.title
                moved.data = change.data ?? moved.data
                moved.status = nil
            }
        }
    }
}

extension Actionable {
    mutating func apply(_ move: Move) {
        state = move.to
        status = move.status ?? status
        title = move.title ?? title
        body = move.body ?? body
        data = move.data ?? data
        links = move.links ?? links
    }
}
