import Foundation

/// The coding agent CLI that the threads run.
public enum AgentProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// The command name on the PATH.
    public var executable: String { rawValue }
}

/// The reasoning effort levels that both CLIs accept.
public enum AgentEffort: String, Codable, CaseIterable, Identifiable, Sendable {
    case low, medium, high, xhigh

    public var id: String { rawValue }
}

/// Your choice of agent. A nil model or effort leaves the default of the CLI.
public struct AgentConfig: Codable, Equatable, Sendable {
    public var provider: AgentProvider
    public var model: String?
    public var effort: AgentEffort?

    public init(provider: AgentProvider = .claude, model: String? = nil, effort: AgentEffort? = nil) {
        self.provider = provider
        self.model = model
        self.effort = effort
    }

    /// An empty model text means the default model.
    public var modelName: String? {
        model.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
    }
}
