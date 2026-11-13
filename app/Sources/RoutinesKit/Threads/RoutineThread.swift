import Foundation

/// The thread of one routine, derived from the steps and never stored. See specs/004-actionables/research.md, section 12.
public struct RoutineThread: Equatable, Sendable {
    public struct Open: Equatable, Sendable, Identifiable {
        public var actionable: Actionable
        public var question: Step
        public var id: String { question.id }
    }

    public struct Answered: Equatable, Sendable, Identifiable {
        public var actionable: Actionable
        public var question: Step
        /// The `answered` or `denied` step after the question.
        public var answer: Step
        public var id: String { question.id }
    }

    /// The routine id, or nil for the No owner thread.
    public var routine: String?
    public var open: [Open]
    /// Newest first.
    public var answered: [Answered]
    /// The actionables of the thread. For No owner, each actionable without a loaded routine.
    public var members: [Actionable]

    public var count: Int { open.count }

    /// `loaded` names the loaded routines, so the actionables of a gone routine join No owner.
    public static func build(routine: String?, actionables: [Actionable], loaded: Set<String>? = nil) -> RoutineThread {
        let members = actionables.filter { actionable in
            guard let routine else { return actionable.owner.map { !(loaded?.contains($0) ?? true) } ?? true }
            return actionable.owner == routine
        }
        let open = members.compactMap { actionable -> Open? in
            guard actionable.state == .waitingOnYou, let last = actionable.steps.last, last.question != nil else { return nil }
            return Open(actionable: actionable, question: last)
        }
        let answered = members.flatMap { actionable in
            zip(actionable.steps, actionable.steps.dropFirst()).compactMap { question, answer -> Answered? in
                guard question.question != nil, answer.action == .answered || answer.action == .denied else { return nil }
                return Answered(actionable: actionable, question: question, answer: answer)
            }
        }
        return RoutineThread(
            routine: routine, open: open.sorted { $0.question.at > $1.question.at }, answered: answered.sorted { $0.answer.at > $1.answer.at },
            members: members)
    }
}
