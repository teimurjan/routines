import Foundation

/// One `actionables.*` or `board.*` call of a plugin, after the bridge decoded it.
enum ActionableCall: Sendable {
    case list(states: [Actionable.State]?, past: Bool)
    case get(String)
    case move(String, transition: String, Move)
    case request(String, transition: String, text: String?)
    case handoff(String, Handoff)
    case boardUpsert(Card)
    case boardRemove(String)
    case boardList

    var isBoard: Bool {
        switch self {
        case .boardUpsert, .boardRemove, .boardList: true
        default: false
        }
    }

    var moves: Bool {
        switch self {
        case .move, .request, .handoff: true
        default: false
        }
    }
}

extension PluginHost {
    /// The answer is JSON text. A plugin reaches only the actionables that it owns or owned (FR-004, FR-012).
    func handle(_ call: ActionableCall, pluginId: String, trigger: String) -> Result<String, HostError> {
        guard let plugin = plugin(pluginId) else { return .failure(Refusal.noRoutine(pluginId).error) }
        let role = plugin.manifest.role
        if call.moves, role == .source { return .failure(Refusal.sourceCannotMove.error) }
        if call.isBoard, role != .legacy { return .failure(.failed("the board calls are only for plugins without actionables")) }
        switch call {
        case .list(let states, let past):
            let owned = actionables.owned(by: pluginId).filter { states?.contains($0.state) ?? true }.map { StoredActionable($0) }
            let earlier = past ? actionables.past(of: pluginId).filter { states?.contains($0.state) ?? true }.map { StoredActionable($0, readOnly: true) } : []
            return .success(Reply.encode(owned + earlier) ?? "[]")
        case .get(let id):
            guard let actionable = actionables.actionable(id), actionable.owner == pluginId || actionable.pastOwners.contains(pluginId) else { return .success("null") }
            return .success(Reply.json(StoredActionable(actionable, readOnly: actionable.owner != pluginId)))
        case .move(let id, let transition, let move):
            return actionables.apply(move, transition: transition, to: id, by: pluginId, manifest: plugin.manifest, trigger: trigger, handles: handles)
                .map { Reply.json(StoredActionable($0)) }
        case .request(let id, let transition, let text):
            switch submit(.transition(transition, of: id, routine: pluginId, source: .selfRequest, text: text, at: now())) {
            case .ask: return .success(Reply.json("asked"))
            case .refuse(let refusal): return .failure(refusal.error)
            default: return .success(Reply.json("queued"))
            }
        case .handoff(let id, let change):
            return actionables.handoff(change, of: id, by: pluginId, handles: handles, trigger: trigger).map { moved in
                // The new owner starts at once (FR-017).
                if let owner = moved.owner { submit(.run(owner, source: .routine, at: now())) }
                return Reply.json(StoredActionable(moved, readOnly: true))
            }
        case .boardUpsert(let card): return boardAdapter.upsert(card, pluginId: pluginId, trigger: trigger).map { "null" }
        case .boardRemove(let id): return boardAdapter.remove(id, pluginId: pluginId, trigger: trigger).map { "null" }
        case .boardList: return .success(Reply.encode(boardAdapter.cards(of: pluginId)) ?? "[]")
        }
    }
}
