import Foundation

/// Each request reaches the host here: build the world, decide, record, act. See specs/004-actionables/contracts/entrance.md.
extension PluginHost {
    /// The answer of a transition or a plugin action: the status line of the plugin, or the reason that it failed.
    public typealias ActionFinished = @MainActor (Result<String?, HostError>) -> Void

    @discardableResult
    public func submit(_ trigger: Trigger, finished: @escaping ActionFinished = { _ in }) -> Decision {
        let decision = Policy.decide(trigger, world(for: trigger))
        decisions.record(trigger, decision)
        switch decision {
        case .startRun:
            advance(trigger.routine, trigger: trigger)
            finished(.success(nil))
        case .queueRun:
            queuedRuns[trigger.routine] = trigger
            advance(trigger.routine, trigger: trigger)
            finished(.success(nil))
        case .merge: finished(.success(nil))
        case .callTransition: callTransition(trigger, finished: finished)
        case .callAction: callAction(trigger, finished: finished)
        case .ask(let transition): ask(transition, trigger: trigger, finished: finished)
        case .refuse(let refusal): finished(.failure(refusal.error))
        }
        return decision
    }

    func world(for trigger: Trigger) -> Policy.World {
        let manifests = Dictionary(plugins.map { ($0.id, $0.manifest) }, uniquingKeysWith: { first, _ in first })
        let blockers = Dictionary(uniqueKeysWithValues: plugins.compactMap { plugin in blocker(plugin.id).map { (plugin.id, $0) } })
        return Policy.World(
            manifests: manifests, handles: handles, blockers: blockers, actionable: trigger.actionable.flatMap(actionables.actionable),
            allowList: manifests[trigger.routine].map { allowList.allowed(trigger.routine, manifest: $0) } ?? [],
            lifecycle: lifecycles[trigger.routine] ?? .idle)
    }

    // MARK: Runs

    private func advance(_ routine: String, trigger: Trigger) {
        let (next, effect) = (lifecycles[routine] ?? .idle).next(on: .trigger)
        lifecycles[routine] = next
        if effect == .start { startRun(routine, trigger: trigger) }
    }

    private func startRun(_ routine: String, trigger: Trigger) {
        guard let plugin = plugin(routine) else { return runEnded(routine) }
        let record = runs.start(pluginId: routine, kind: .run, trigger: trigger.legacyName)
        let context = context(plugin, trigger: trigger)
        Task {
            let result = await call(plugin, function: "run", arguments: [context], logFile: record.logFile, trigger: trigger.id)
            let (outcome, message) = Self.outcome(of: result)
            runs.finish(record.id, outcome: outcome, message: message)
            callEnded(trigger: trigger.id, logFile: record.logFile, routine: routine)
            runEnded(routine)
        }
    }

    /// The queued run starts now, if its routine can still run.
    private func runEnded(_ routine: String) {
        let (next, effect) = (lifecycles[routine] ?? .idle).next(on: .ended)
        lifecycles[routine] = next
        guard effect == .start, let queued = queuedRuns.removeValue(forKey: routine) else { return }
        guard blocker(routine) == nil else {
            lifecycles[routine] = .idle
            return
        }
        startRun(routine, trigger: queued)
    }

    // MARK: Transitions and actions

    private func callTransition(_ trigger: Trigger, finished: @escaping ActionFinished) {
        guard let plugin = plugin(trigger.routine), let id = trigger.actionable, let transition = trigger.transition,
            var actionable = actionables.actionable(id)
        else { return finished(.failure(.failed("the transition lost its actionable"))) }
        let asked = trigger.grant == nil ? nil : actionable.steps.last
        let question = trigger.source == .answer ? actionable.steps.last?.question : nil
        let history = Self.history(actionable.steps)
        let text = trigger.text ?? asked?.question?.input
        if trigger.source == .answer {
            if trigger.grant == .always { allowList.set(true, transition: transition, routine: trigger.routine) }
            let back = asked?.from ?? actionable.state
            let step = Step.Draft(action: .answered, actor: "you", trigger: trigger.id, answer: trigger.text ?? "Allow")
            guard case .success(let answered) = actionables.update(id, step: step, changes: { $0.state = back }) else {
                return finished(.failure(.failed("the answer to actionable \(id) was not stored")))
            }
            actionable = answered
        }
        let legacy = plugin.manifest.role == .legacy
        let event = legacy
            ? Reply.json(ActionEvent(cardId: actionable.dedupeKey, actionId: transition, text: text))
            : Reply.json(TransitionEvent(actionable: StoredActionable(actionable), transition: transition, text: text, session: question?.session, history: history))
        let show: @MainActor (String?) -> Void = { [weak self] status in self?.actionables.setStatus(status, of: id) }
        queueCall(
            plugin, key: "\(plugin.id)/\(legacy ? actionable.dedupeKey : id)", trigger: trigger, recordName: "\(id):\(transition)",
            function: legacy ? "onAction" : "onTransition", event: event, show: show
        ) { [weak self] json in
            guard let self, !legacy else { return Self.statusLine(json) }
            return self.applyHandled(json, transition: transition, actionable: id, plugin: plugin, trigger: trigger.id)
        } finished: { finished($0) }
    }

    private func callAction(_ trigger: Trigger, finished: @escaping ActionFinished) {
        guard let plugin = plugin(trigger.routine), let actionId = trigger.transition else { return finished(.failure(.failed("the action has no id"))) }
        let routine = plugin.id
        queueCall(
            plugin, key: routine, trigger: trigger, recordName: actionId, function: "onPluginAction",
            event: Reply.json(PluginActionEvent(actionId: actionId, text: trigger.text)),
            show: { [weak self] status in self?.pluginActionStatus[routine] = status }, apply: Self.statusLine, finished: finished)
    }

    /// The move of a handler becomes one step. A failed handler or a bad move adds no step.
    private func applyHandled(_ json: String?, transition: String, actionable: String, plugin: PluginEntry, trigger: String) -> Result<String?, HostError> {
        guard let json, let data = json.data(using: .utf8), let reply = try? Reply.decoder.decode(MoveReply.self, from: data) else {
            return .failure(.failed("onTransition must return a Result of a move"))
        }
        guard reply.ok, let move = reply.value else { return .failure(.failed(reply.error ?? "the transition failed")) }
        return actionables.apply(
            move, transition: transition, to: actionable, by: plugin.id, manifest: plugin.manifest, trigger: trigger, kind: .handled, handles: handles)
            .map { $0.status }
    }

    /// Runs a handler after the earlier handlers of the same plugin. A run of the plugin does not block it.
    private func queueCall(
        _ plugin: PluginEntry, key: String, trigger: Trigger, recordName: String, function: String, event: String,
        show: @escaping @MainActor (String?) -> Void, apply: @escaping @MainActor (String?) -> Result<String?, HostError>,
        finished: @escaping ActionFinished
    ) {
        pendingActions.insert(key)
        show("Working on it…")
        let context = context(plugin, trigger: trigger)
        let previous = actionQueues[plugin.id]
        actionQueues[plugin.id] = Task {
            await previous?.value
            let record = runs.start(pluginId: plugin.id, kind: .action, trigger: recordName)
            let result = await call(plugin, function: function, arguments: [event, context], logFile: record.logFile, trigger: trigger.id)
            let (outcome, message) = Self.outcome(of: result)
            let applied = outcome == .failed ? .failure(.failed(message ?? "the action failed")) : apply(try? result.get())
            switch applied {
            case .success(let status):
                runs.finish(record.id, outcome: .succeeded, message: status ?? message)
                show(status ?? message)
            case .failure(let error):
                runs.finish(record.id, outcome: .failed, message: error.description)
                RunLog(path: record.logFile, pluginId: plugin.id).write("failed: \(error)")
                show("Error: \(error)")
            }
            pendingActions.remove(key)
            callEnded(trigger: trigger.id, logFile: record.logFile, routine: plugin.id)
            finished(applied.map { $0 ?? message })
        }
    }

    private static func statusLine(_ json: String?) -> Result<String?, HostError> {
        let (_, message) = outcome(of: .success(json))
        return .success(message)
    }

    /// The steps since the last answer, for a session that cannot resume.
    static func history(_ steps: [Step]) -> [Step] {
        guard let last = steps.lastIndex(where: { $0.action == .answered }) else { return steps }
        return Array(steps[(last + 1)...])
    }

    // MARK: Permission questions

    /// The actionable waits on you with a permission question (FR-024).
    private func ask(_ transition: String, trigger: Trigger, finished: @escaping ActionFinished) {
        guard let plugin = plugin(trigger.routine), let id = trigger.actionable, let actionable = actionables.actionable(id),
            let declaration = plugin.manifest.transition(transition)
        else { return finished(.failure(.failed("the question lost its actionable"))) }
        let question = Question(
            text: "\(plugin.manifest.name) wants to \(declaration.label): \(actionable.title)", permission: transition, input: trigger.text)
        let step = Step.Draft(action: .asked, actor: "host", trigger: trigger.id, question: question)
        switch actionables.update(id, step: step, changes: { $0.state = .waitingOnYou }) {
        case .success: finished(.success("asked"))
        case .failure(let error): finished(.failure(error))
        }
    }

    /// Deny moves the actionable back to its state before the question, and no handler runs.
    public func deny(question stepId: String, of actionableId: String) -> Result<Void, HostError> {
        guard let actionable = actionables.actionable(actionableId) else { return .failure(Refusal.noActionable(actionableId).error) }
        guard actionable.state == .waitingOnYou else { return .failure(Refusal.notWaiting(actionable: actionableId).error) }
        guard let asked = actionable.steps.last, asked.id == stepId, asked.action == .asked else { return .failure(Refusal.staleQuestion.error) }
        let step = Step.Draft(action: .denied, actor: "you", trigger: UUID().uuidString)
        return actionables.update(actionableId, step: step) { $0.state = asked.from }.map { _ in () }
    }

    /// Your answer to a question or a permission question, as a trigger with the source `answer`.
    @discardableResult
    public func answer(question stepId: String, of actionableId: String, text: String?, grant: Trigger.Grant? = nil, finished: @escaping ActionFinished = { _ in }) -> Decision {
        let actionable = actionables.actionable(actionableId)
        let question = actionable?.steps.first { $0.id == stepId }?.question
        let trigger = Trigger(
            routine: actionable?.owner ?? "", source: .answer, work: .transition, actionable: actionableId,
            transition: question?.permission ?? question?.transition, text: text, answers: stepId, grant: question?.permission == nil ? nil : grant ?? .once,
            at: now())
        return submit(trigger, finished: finished)
    }

    // MARK: Steps

    /// A question posts a notification that opens it in its routine thread (FR-032).
    func stepAdded(_ step: Step, of actionable: Actionable) {
        guard let question = step.question, let owner = actionable.owner else { return }
        let item = notifications.add(pluginId: owner, title: actionable.title, body: question.text, cardId: actionable.id, stepId: step.id)
        deliver(item)
    }
}

/// An actionable as a plugin reads it.
struct StoredActionable: Encodable {
    var actionable: Actionable
    var readOnly = false
    var allowed: [String]?

    init(_ actionable: Actionable, readOnly: Bool = false, allowed: [String]? = nil) {
        self.actionable = actionable
        self.readOnly = readOnly
        self.allowed = allowed
    }

    private enum Keys: String, CodingKey { case readOnly, allowed }

    func encode(to encoder: Encoder) throws {
        try actionable.encode(to: encoder)
        var values = encoder.container(keyedBy: Keys.self)
        try values.encode(readOnly, forKey: .readOnly)
        try values.encodeIfPresent(allowed, forKey: .allowed)
    }
}

struct TransitionEvent: Encodable {
    var actionable: StoredActionable
    var transition: String
    var text: String?
    var session: Session?
    var history: [Step]
}

private struct MoveReply: Decodable {
    var ok: Bool
    var value: Move?
    var error: String?
}

extension PluginHost {
    /// Runs a request of another program through the entrance, and writes the answer to its reply file. It shows no dialog.
    public func performExternal(_ request: ExternalAction) {
        let reply = { (text: String) in
            guard let file = request.replyFile else { return }
            try? FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: URL(fileURLWithPath: file), options: .atomic)
        }
        if case .failure(let error) = request.checkReply(repliesDir: paths.file("replies").path) { return reply("Error: \(error)") }
        submit(request.trigger(at: now())) { result in
            switch result {
            case .success(let status): reply(status ?? "Done.")
            case .failure(let error): reply("Error: \(error)")
            }
        }
    }
}
