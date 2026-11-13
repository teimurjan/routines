import Foundation

/// One pair of a kind and a state, which one routine handles (FR-009).
public struct HandleKey: Hashable, Sendable {
    public var kind: String
    public var state: Actionable.State

    public init(kind: String, state: Actionable.State) {
        self.kind = kind
        self.state = state
    }
}

public struct HandlesTable: Equatable, Sendable {
    public var table: [HandleKey: String]
    /// The schema of each declared kind, by kind.
    public var kinds: [String: KindSchema]
    /// The plugins that the table refused, with the conflict.
    public var problems: [String: String]

    public static let empty = HandlesTable(table: [:], kinds: [:], problems: [:])

    public func handler(kind: String, state: Actionable.State) -> String? {
        table[HandleKey(kind: kind, state: state)]
    }

    /// A kind that no plugin declares accepts any object.
    public func schema(of kind: String) -> KindSchema {
        kinds[kind] ?? .anyObject
    }
}

public enum Handles {
    /// In catalog order, so the first plugin with a kind or a pair wins. A refused plugin adds nothing to the table.
    public static func build(_ entries: [PluginEntry]) -> HandlesTable {
        var result = HandlesTable.empty
        var declaredBy: [String: String] = [:]
        for entry in entries where entry.problem == nil {
            let manifest = entry.manifest
            if let kind = manifest.kinds.first(where: { declaredBy[$0] != nil }) {
                result.problems[entry.id] = "the kind \(kind) is already declared by \(declaredBy[kind]!)"
                continue
            }
            let keys = manifest.handles.flatMap { handle in handle.states.map { HandleKey(kind: handle.kind, state: $0) } }
            if let taken = keys.first(where: { result.table[$0] != nil }) {
                result.problems[entry.id] = "\(result.table[taken]!) already handles \(taken.kind) in \(taken.state.rawValue)"
                continue
            }
            for key in keys { result.table[key] = entry.id }
            for kind in manifest.kinds { declaredBy[kind] = entry.id }
            result.kinds.merge(entry.kinds) { first, _ in first }
        }
        return result
    }
}
