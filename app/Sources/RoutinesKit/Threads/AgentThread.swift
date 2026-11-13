import Foundation

/// One conversation with the coding agent. Its provider stays fixed, because a session of one CLI does not resume in the other.
public struct AgentThread: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var provider: AgentProvider
    /// The session id of the CLI, which the next turn resumes.
    public var sessionId: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var items: [ThreadItem]

    public init(id: String = UUID().uuidString, provider: AgentProvider, createdAt: Date = Date()) {
        self.id = id
        self.provider = provider
        self.createdAt = createdAt
        updatedAt = createdAt
        items = []
    }

    static let titleLength = 60

    public var title: String {
        guard let first = items.first(where: { $0.kind == .user })?.text else { return "New thread" }
        let line = first.split(whereSeparator: \.isNewline).first.map(String.init) ?? first
        return line.count > Self.titleLength ? String(line.prefix(Self.titleLength)) + "…" : line
    }

    public mutating func apply(_ event: AgentEvent, now: Date = Date()) {
        updatedAt = now
        switch event {
        case .session(let id):
            sessionId = id
        case .item(let item):
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item } else { items.append(item) }
        case .output(let id, let text, let failed):
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].text = text
            items[index].state = failed ? .failed : .done
        case .finished(let error):
            settleRunningSteps()
            if let error { items.append(ThreadItem(kind: .error, text: error, state: .failed, date: now)) }
        }
    }

    /// A step without a result did not finish, for example after a stop or a quit of the app.
    public mutating func settleRunningSteps() {
        for index in items.indices where items[index].state == .running { items[index].state = .failed }
    }

    /// The routines that a file change of this thread touched, in the order of the first change.
    public var touchedPlugins: [String] {
        items.filter { $0.kind == .fileChange }.flatMap { Self.pluginIds(in: $0.title) }.reduce(into: []) { ids, id in
            if !ids.contains(id) { ids.append(id) }
        }
    }

    static func pluginIds(in paths: String) -> [String] {
        paths.matches(of: /(?:^|[\s\/])plugins\/([a-z0-9][a-z0-9-]*)\//).map { String($0.output.1) }
    }
}

public struct ThreadItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case user, message, reasoning, command, fileChange, tool, error }
    public enum State: String, Codable, Sendable { case running, done, failed }

    public var id: String
    public var kind: Kind
    /// The command, the changed paths or the tool name. A message has no title.
    public var title: String
    /// The message text or the output of a tool.
    public var text: String
    public var state: State
    public var date: Date
    /// The routine items that a message of yours asks about.
    public var references: [ItemReference]?

    public init(
        id: String = UUID().uuidString, kind: Kind, title: String = "", text: String = "", state: State = .done, date: Date = Date(),
        references: [ItemReference]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.state = state
        self.date = date
        self.references = references
    }

    /// A step of the agent's work, which the thread folds into a group between messages.
    public var isStep: Bool {
        [.command, .fileChange, .tool, .reasoning].contains(kind)
    }
}

/// One item of a routine, which you add to a message with a Command-click.
public struct ItemReference: Codable, Equatable, Hashable, Sendable {
    public var pluginId: String
    public var cardId: String
    public var title: String

    public init(pluginId: String, cardId: String, title: String) {
        self.pluginId = pluginId
        self.cardId = cardId
        self.title = title
    }
}

/// A message, an error or a run of steps between them.
public enum ThreadSegment: Equatable, Identifiable, Sendable {
    case entry(ThreadItem)
    case steps([ThreadItem])

    public var id: String {
        switch self {
        case .entry(let item): item.id
        case .steps(let steps): steps.first?.id ?? ""
        }
    }
}

extension AgentThread {
    /// The items in order, with each run of steps in one segment.
    public var segments: [ThreadSegment] {
        items.reduce(into: []) { segments, item in
            guard item.isStep else { return segments.append(.entry(item)) }
            if case .steps(let steps) = segments.last {
                segments[segments.count - 1] = .steps(steps + [item])
            } else {
                segments.append(.steps([item]))
            }
        }
    }
}

/// One change that a line of CLI output makes to a thread.
public enum AgentEvent: Equatable, Sendable {
    case session(String)
    /// Adds the item, or replaces the item with the same id.
    case item(ThreadItem)
    /// Ends a running tool item with its output.
    case output(id: String, text: String, failed: Bool)
    case finished(error: String?)
}
