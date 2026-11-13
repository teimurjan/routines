import Foundation

/// One request to start a run, a transition or a plugin action, from any caller. See specs/004-actionables/contracts/entrance.md.
public struct Trigger: Codable, Equatable, Sendable, Identifiable {
    /// Who asked.
    public enum Source: String, Codable, Sendable, CaseIterable {
        case clock, ui
        /// `runSoon` and `actionables.request` of the routine itself.
        case selfRequest = "self"
        case routine, external, answer, source
    }

    public enum Work: String, Codable, Sendable {
        case run, transition
        /// A plugin action of the manifest, with no actionable.
        case action
    }

    /// Allow on a permission question.
    public enum Grant: String, Codable, Sendable { case once, always }

    public var id: String
    public var routine: String
    public var source: Source
    public var work: Work
    public var actionable: String?
    /// The transition, or the plugin action for the work `action`.
    public var transition: String?
    public var text: String?
    /// The id of the question step, for the source `answer`.
    public var answers: String?
    public var grant: Grant?
    public var at: Date

    public init(
        id: String = UUID().uuidString, routine: String, source: Source, work: Work, actionable: String? = nil, transition: String? = nil,
        text: String? = nil, answers: String? = nil, grant: Grant? = nil, at: Date
    ) {
        self.id = id
        self.routine = routine
        self.source = source
        self.work = work
        self.actionable = actionable
        self.transition = transition
        self.text = text
        self.answers = answers
        self.grant = grant
        self.at = at
    }

    public static func run(_ routine: String, source: Source, at: Date) -> Trigger {
        Trigger(routine: routine, source: source, work: .run, at: at)
    }

    public static func transition(_ id: String, of actionable: String, routine: String, source: Source, text: String? = nil, at: Date) -> Trigger {
        Trigger(routine: routine, source: source, work: .transition, actionable: actionable, transition: id, text: text, at: at)
    }

    /// The `trigger` string of `RunContext` today.
    public var legacyName: String {
        switch source {
        case .clock: "schedule"
        case .selfRequest: "soon"
        case .ui: "action"
        default: source.rawValue
        }
    }
}
