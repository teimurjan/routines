import Foundation

/// Starts at most one poll a minute, and never while a poll runs. See "One poll" in specs/004-actionables/contracts/sources.md.
@MainActor
final class Poller {
    static let interval: TimeInterval = 60
    static let timeout: Duration = .seconds(50)
    private(set) var lastStart: Date?
    private(set) var isPolling = false
    private let poll: @MainActor () async -> Void

    init(poll: @escaping @MainActor () async -> Void) {
        self.poll = poll
    }

    func tick(now: Date) {
        guard !isPolling, lastStart.map({ now.timeIntervalSince($0) >= Self.interval }) ?? true else { return }
        lastStart = now
        isPolling = true
        Task {
            await poll()
            isPolling = false
        }
    }
}

/// One item that a source returns.
public struct PollItem: Codable, Equatable, Sendable {
    public var dedupeKey: String
    public var kind: String
    public var title: String
    public var body: String?
    public var data: JSONValue
    public var links: [CardLink]?
}

private struct PollAnswer: Decodable {
    var items: [PollItem]
    var cursor: JSONValue?
}

private struct Envelope<Value: Decodable>: Decodable {
    var ok: Bool
    var value: Value?
    var error: String?

    static func decode(_ result: Result<String?, HostError>) -> Result<Value, HostError> {
        result.flatMap { json in
            guard let json, let data = json.data(using: .utf8), let envelope = try? Reply.decoder.decode(Self.self, from: data) else {
                return .failure(.failed("the function must return a Result of the contract"))
            }
            guard envelope.ok, let value = envelope.value else { return .failure(.failed(envelope.error ?? "the function failed")) }
            return .success(value)
        }
    }
}

extension PluginHost {
    /// The poller has its own minute, so an outside item becomes an actionable within 90 seconds (SC-002). It rests while the Mac sleeps.
    public func startPolling() {
        let poller = Poller { [weak self] in await self?.pollOnce() }
        self.poller = poller
        Timer.scheduledTimer(withTimeInterval: Poller.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in if self?.isAsleep == false { self?.poller?.tick(now: Date()) } }
        }
        poller.tick(now: Date())
    }

    /// One poll of all sources with one agent call. Each source keeps its cursor until its items are stored.
    public func pollOnce() async {
        let sources = plugins.filter { $0.manifest.role == .source && blocker($0.id) == nil }
        guard !sources.isEmpty else { return }
        let pollId = UUID().uuidString
        let logFile = paths.file("runs/polls/\(DecisionLog.day(now())).log").path
        let log = RunLog(path: logFile, pluginId: "poll")
        log.write("poll started: \(sources.map(\.id).joined(separator: ", "))")
        defer { log.close() }

        var requests: [(source: String, request: PollRequest, tools: [String])] = []
        for source in sources {
            let event = Reply.json(PollEvent(cursor: cursors.cursor(of: source.id).cursor, output: nil))
            let answer = await call(source, function: "pollRequest", arguments: [event, context(source, trigger: .run(source.id, source: .source, at: now()))], logFile: logFile, trigger: pollId)
            switch Envelope<PollRequest>.decode(answer) {
            case .success(let request): requests.append((source.id, request, source.manifest.source?.tools ?? []))
            case .failure(let error):
                log.write("\(source.id): pollRequest failed: \(error)")
                cursors.failed(source.id, error: "pollRequest: \(error)")
            }
        }
        guard let plan = PollPlan.build(requests: requests) else { return log.write("no source asked to poll") }

        let output = await runAgent(plan.command(), stdin: plan.prompt, cwd: paths.dataDir, timeout: Poller.timeout).flatMap(AgentRunner.structuredOutput)
        let parts: [String: JSONValue]
        switch output {
        case .success(let value): parts = PollPlan.split(output: value, plan: plan)
        case .failure(let error):
            log.write("poll failed: \(error)")
            for id in plan.sources { cursors.failed(id, error: error.description) }
            return
        }

        var owners: Set<String> = []
        for source in sources where plan.sources.contains(source.id) {
            let cursor = cursors.cursor(of: source.id).cursor
            let event = Reply.json(PollEvent(cursor: cursor, output: parts[source.id] ?? .null))
            let answer = await call(source, function: "onPoll", arguments: [event, context(source, trigger: .run(source.id, source: .source, at: now()))], logFile: logFile, trigger: pollId)
            switch Envelope<PollAnswer>.decode(answer).flatMap({ answer in store(answer.items, from: source, trigger: pollId).map { (answer, $0) } }) {
            case .success(let (answer, newOwners)):
                cursors.moved(source.id, to: answer.cursor ?? cursor, at: now())
                owners.formUnion(newOwners)
                log.write("\(source.id): \(answer.items.count) items")
            case .failure(let error):
                log.write("\(source.id): \(error)")
                cursors.failed(source.id, error: error.description)
            }
        }
        for owner in owners.sorted() { submit(.run(owner, source: .source, at: now())) }
    }

    /// Checks each item first, so a bad item stores none of its poll. Returns the owners of the new actionables.
    func store(_ items: [PollItem], from source: PluginEntry, trigger: String) -> Result<Set<String>, HostError> {
        let kinds = source.manifest.source?.kinds ?? []
        var keys: Set<String> = []
        for item in items {
            guard kinds.contains(item.kind) else { return .failure(.failed("the kind \(item.kind) is not in source.kinds")) }
            guard keys.insert(item.dedupeKey).inserted else { return .failure(.failed("the key \(item.dedupeKey) came twice in one poll")) }
            if case .failure(let error) = handles.schema(of: item.kind).validate(item.data) { return .failure(error) }
        }
        var owners: Set<String> = []
        for item in items {
            let stored: Result<Actionable, HostError>
            if let known = actionables.find(source: source.id, key: item.dedupeKey) {
                // The state stays, also for a closed actionable. The owner decides (edge case of the spec).
                stored = actionables.update(known.id, step: Step.Draft(action: .updated, actor: source.id, trigger: trigger)) { $0.fill(from: item) }
            } else {
                let owner = handles.handler(kind: item.kind, state: .new)
                stored = actionables.create(
                    kind: item.kind, source: source.id, dedupeKey: item.dedupeKey, owner: owner, state: .new, title: BoardAdapter.title(item.title),
                    step: Step.Draft(action: .created, actor: source.id, trigger: trigger)
                ) { $0.fill(from: item) }
                if let owner, case .success = stored { owners.insert(owner) }
            }
            if case .failure(let error) = stored { return .failure(error) }
        }
        return .success(owners)
    }
}

private struct PollEvent: Encodable {
    var cursor: JSONValue
    var output: JSONValue?
}

extension Actionable {
    mutating func fill(from item: PollItem) {
        title = BoardAdapter.title(item.title)
        body = item.body
        data = item.data
        links = item.links ?? links
    }
}
