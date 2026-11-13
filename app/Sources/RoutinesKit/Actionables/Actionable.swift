import Foundation

/// One item of work that the host stores. See specs/004-actionables/data-model.md.
public struct Actionable: Codable, Equatable, Sendable, Identifiable {
    /// The place of an actionable in the shared lifecycle.
    public enum State: String, Codable, CaseIterable, Sendable {
        case new
        case ready
        case working
        case waitingOnYou = "waiting-on-you"
        case waitingOnOthers = "waiting-on-others"
        case done
        case failed
        case dropped

        public var isClosed: Bool { self == .done || self == .failed || self == .dropped }

        public static var open: [State] { allCases.filter { !$0.isClosed } }

        /// The board column of today, for the plugins that still use the board.
        public init(column: Column) {
            switch column {
            case .planned: self = .ready
            case .working: self = .working
            case .needsYou: self = .waitingOnYou
            case .done: self = .done
            case .failed: self = .failed
            }
        }

        public var column: Column {
            switch self {
            case .new, .ready: .planned
            case .working, .waitingOnOthers: .working
            case .waitingOnYou: .needsYou
            case .done, .dropped: .done
            case .failed: .failed
            }
        }
    }

    public var id: String
    public var kind: String
    public var source: String
    public var dedupeKey: String
    /// Nil means that no routine handles it, or that its routine is gone.
    public var owner: String?
    public var pastOwners: [String]
    public var state: State
    public var title: String
    public var body: String?
    public var status: String?
    public var tags: [String]?
    public var links: [CardLink]
    public var images: [String]?
    public var date: String?
    public var progress: Double?
    public var data: JSONValue
    public var steps: [Step]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String, kind: String, source: String, dedupeKey: String, owner: String?, pastOwners: [String] = [], state: State, title: String,
        body: String? = nil, status: String? = nil, tags: [String]? = nil, links: [CardLink] = [], images: [String]? = nil, date: String? = nil,
        progress: Double? = nil, data: JSONValue = .object([:]), steps: [Step] = [], createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.dedupeKey = dedupeKey
        self.owner = owner
        self.pastOwners = pastOwners
        self.state = state
        self.title = title
        self.body = body
        self.status = status
        self.tags = tags
        self.links = links
        self.images = images
        self.date = date
        self.progress = progress
        self.data = data
        self.steps = steps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The owner is null, not absent, so a page can tell no owner from an old host.
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(kind, forKey: .kind)
        try values.encode(source, forKey: .source)
        try values.encode(dedupeKey, forKey: .dedupeKey)
        try values.encode(owner, forKey: .owner)
        try values.encode(pastOwners, forKey: .pastOwners)
        try values.encode(state, forKey: .state)
        try values.encode(title, forKey: .title)
        try values.encodeIfPresent(body, forKey: .body)
        try values.encodeIfPresent(status, forKey: .status)
        try values.encodeIfPresent(tags, forKey: .tags)
        try values.encode(links, forKey: .links)
        try values.encodeIfPresent(images, forKey: .images)
        try values.encodeIfPresent(date, forKey: .date)
        try values.encodeIfPresent(progress, forKey: .progress)
        try values.encode(data, forKey: .data)
        try values.encode(steps, forKey: .steps)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
    }

    /// The owners in order, oldest first. The last one is the owner now.
    var owners: [String] { pastOwners + (owner.map { [$0] } ?? []) }

    /// The owner when the step was made. A hand-off step belongs to the owner that sent it.
    public func owner(atStep stepId: String) -> String? {
        guard let index = steps.firstIndex(where: { $0.id == stepId }) else { return nil }
        let handoffs = steps[..<index].count { $0.action == .handoff }
        let owners = owners
        return handoffs < owners.count ? owners[handoffs] : owner
    }

    /// The card shape, for the board calls and the `items` of a snapshot.
    public func card(id cardId: String) -> Card {
        Card(
            id: cardId, title: title, body: body, column: state.column, progress: progress, date: date, tags: tags, links: links.isEmpty ? nil : links,
            images: images, status: status, data: data == .object([:]) ? nil : data, updatedAt: updatedAt)
    }
}

/// One change of an actionable. A state change adds exactly one step (FR-003).
public struct Step: Codable, Equatable, Sendable, Identifiable {
    public enum Action: Equatable, Hashable, Sendable, Codable, CustomStringConvertible {
        case transition(String)
        case handoff, created, updated, asked, answered, denied, board, migrated

        private static let plain: [String: Action] = [
            "handoff": .handoff, "created": .created, "updated": .updated, "asked": .asked, "answered": .answered, "denied": .denied,
            "board": .board, "migrated": .migrated,
        ]
        private static let prefix = "transition:"

        public init(from decoder: Decoder) throws {
            let text = try decoder.singleValueContainer().decode(String.self)
            if text.hasPrefix(Self.prefix) {
                self = .transition(String(text.dropFirst(Self.prefix.count)))
            } else if let action = Self.plain[text] {
                self = action
            } else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown step action \(text)"))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var value = encoder.singleValueContainer()
            try value.encode(description)
        }

        public var description: String {
            switch self {
            case .transition(let id): Self.prefix + id
            default: Self.plain.first { $0.value == self }?.key ?? "unknown"
            }
        }
    }

    /// What the caller of a step gives. The store adds the id, the time and the states.
    public struct Draft: Equatable, Sendable {
        public var action: Action
        public var actor: String
        public var trigger: String
        public var outcome: String?
        public var question: Question?
        public var answer: String?
        public var oldOwner: String?
        public var oldKind: String?

        public init(
            action: Action, actor: String, trigger: String, outcome: String? = nil, question: Question? = nil, answer: String? = nil,
            oldOwner: String? = nil, oldKind: String? = nil
        ) {
            self.action = action
            self.actor = actor
            self.trigger = trigger
            self.outcome = outcome
            self.question = question
            self.answer = answer
            self.oldOwner = oldOwner
            self.oldKind = oldKind
        }
    }

    public var id: String
    public var at: Date
    public var action: Action
    /// A routine id, a source id, `you` or `host`.
    public var actor: String
    /// The id of the decision that started the call.
    public var trigger: String
    public var from: Actionable.State
    public var to: Actionable.State
    public var outcome: String?
    public var question: Question?
    public var answer: String?
    public var oldOwner: String?
    public var oldKind: String?

    public init(id: String, at: Date, draft: Draft, from: Actionable.State, to: Actionable.State) {
        self.id = id
        self.at = at
        action = draft.action
        actor = draft.actor
        trigger = draft.trigger
        self.from = from
        self.to = to
        outcome = draft.outcome
        question = draft.question
        answer = draft.answer
        oldOwner = draft.oldOwner
        oldKind = draft.oldKind
    }
}

/// A question to you. It has `transition` or `permission`, never both.
public struct Question: Codable, Equatable, Sendable {
    public var text: String
    /// The transition that your answer starts.
    public var transition: String?
    public var session: Session?
    /// The transition that waits for Allow, on an `asked` step.
    public var permission: String?
    /// The text of the request that waits for Allow.
    public var input: String?

    public init(text: String, transition: String? = nil, session: Session? = nil, permission: String? = nil, input: String? = nil) {
        self.text = text
        self.transition = transition
        self.session = session
        self.permission = permission
        self.input = input
    }
}

/// The agent session that asked a question.
public struct Session: Codable, Equatable, Sendable {
    public var id: String
    public var cwd: String

    public init(id: String, cwd: String) {
        self.id = id
        self.cwd = cwd
    }
}

/// The end state and the changes that a move or a transition handler returns.
public struct Move: Codable, Equatable, Sendable {
    public var to: Actionable.State
    public var status: String?
    public var title: String?
    public var body: String?
    public var data: JSONValue?
    public var links: [CardLink]?
    public var question: Question?

    public init(
        to: Actionable.State, status: String? = nil, title: String? = nil, body: String? = nil, data: JSONValue? = nil, links: [CardLink]? = nil,
        question: Question? = nil
    ) {
        self.to = to
        self.status = status
        self.title = title
        self.body = body
        self.data = data
        self.links = links
        self.question = question
    }
}

/// A hand-off names the new state and kind, not a routine. The host finds the routine.
public struct Handoff: Codable, Equatable, Sendable {
    public var state: Actionable.State
    public var kind: String?
    public var title: String?
    public var data: JSONValue?

    public init(state: Actionable.State, kind: String? = nil, title: String? = nil, data: JSONValue? = nil) {
        self.state = state
        self.kind = kind
        self.title = title
        self.data = data
    }
}
