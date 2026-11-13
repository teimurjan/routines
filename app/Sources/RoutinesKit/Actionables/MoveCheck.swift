import Foundation

/// The pure checks of a move and a hand-off that a routine asks for in a run.
public enum MoveCheck {
    static let questionLimit = 2000

    /// A move in a run makes only a `read` or `reversible` transition. A question forces the state `waiting-on-you`.
    public static func move(_ move: Move, transition id: String, by routine: String, actionable: Actionable, manifest: Manifest) -> Result<Move, Refusal> {
        guard actionable.owner == routine else { return .failure(.notOwner(routine: routine, actionable: actionable.id)) }
        guard let declaration = manifest.transition(id) else { return .failure(.noTransition(routine: routine, transition: id)) }
        guard declaration.from.contains(actionable.state) else { return .failure(.wrongState(transition: id, state: actionable.state)) }
        if declaration.risk.needsConsent { return .failure(.needsRequest(transition: id, risk: declaration.risk)) }
        return withQuestion(move, routine: routine, manifest: manifest)
    }

    /// The move that a transition handler returns, after the policy allowed its trigger.
    public static func handled(_ move: Move, routine: String, manifest: Manifest) -> Result<Move, Refusal> {
        withQuestion(move, routine: routine, manifest: manifest)
    }

    private static func withQuestion(_ move: Move, routine: String, manifest: Manifest) -> Result<Move, Refusal> {
        guard let question = move.question else { return .success(move) }
        guard (1...questionLimit).contains(question.text.count) else { return .failure(.badQuestion("the question text has 1 to 2,000 characters")) }
        guard question.permission == nil, let id = question.transition else {
            return .failure(.badQuestion("a question names the transition that your answer starts"))
        }
        guard let declaration = manifest.transition(id) else { return .failure(.noTransition(routine: routine, transition: id)) }
        guard declaration.from.contains(.waitingOnYou), declaration.input != nil else {
            return .failure(.badQuestion("the transition \(id) of a question starts from `waiting-on-you` and has `input`"))
        }
        var forced = move
        forced.to = .waitingOnYou
        return .success(forced)
    }

    /// A hand-off names a kind and a state. Exactly one other routine must handle them, and the data must fit the kind (FR-007, FR-008).
    public static func handoff(_ change: Handoff, by routine: String, actionable: Actionable, handles: HandlesTable) -> Result<String, Refusal> {
        guard actionable.owner == routine else { return .failure(.notOwner(routine: routine, actionable: actionable.id)) }
        let kind = change.kind ?? actionable.kind
        guard let handler = handles.handler(kind: kind, state: change.state) else { return .failure(.noHandler(kind: kind, state: change.state)) }
        guard handler != routine else { return .failure(.sameRoutine(routine)) }
        if case .failure(let error) = handles.schema(of: kind).validate(change.data ?? actionable.data) { return .failure(.badData(error.description)) }
        return .success(handler)
    }
}
