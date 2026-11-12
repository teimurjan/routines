import Foundation

/// Whether the chosen CLI can run a turn now, in one line for the Threads page.
public struct AgentStatus: Equatable, Sendable {
    public var ready: Bool
    public var detail: String
    /// A problem that does not stop a turn, for example a missing Bun.
    public var warning: String?
}

public enum AgentHealth {
    public static func check(_ provider: AgentProvider, home: String) async -> AgentStatus {
        let warning = ExecService.which("bun", home: home) == nil ? "Bun is not installed, so the agent cannot build routines. Install it from bun.sh." : nil
        guard ExecService.which(provider.executable, home: home) != nil else {
            return AgentStatus(ready: false, detail: "\(provider.name) is not installed.", warning: warning)
        }
        let env = AgentEnvironment.extra(provider, home: home)
        switch provider {
        case .claude:
            let status = await ExecService.run(ExecRequest(cmd: ["claude", "auth", "status", "--json"], env: env), home: home)
            return AgentStatus(ready: claudeLoggedIn(status), detail: claudeDetail(status), warning: warning)
        case .codex:
            let status = await ExecService.run(ExecRequest(cmd: ["codex", "login", "status"], env: env), home: home)
            if case .success(let text) = status { return AgentStatus(ready: true, detail: text.isEmpty ? "Logged in." : text, warning: warning) }
            return AgentStatus(ready: false, detail: "Not logged in. Run codex login in Terminal.", warning: warning)
        }
    }

    private struct ClaudeAuth: Decodable {
        var loggedIn: Bool
        var subscriptionType: String?
    }

    private static func claudeAuth(_ status: Result<String, HostError>) -> ClaudeAuth? {
        guard case .success(let text) = status else { return nil }
        return try? JSONDecoder().decode(ClaudeAuth.self, from: Data(text.utf8))
    }

    private static func claudeLoggedIn(_ status: Result<String, HostError>) -> Bool {
        claudeAuth(status)?.loggedIn ?? false
    }

    private static func claudeDetail(_ status: Result<String, HostError>) -> String {
        guard let auth = claudeAuth(status), auth.loggedIn else { return "Not logged in. Run claude in Terminal and log in." }
        return auth.subscriptionType.map { "Logged in with the \($0) plan." } ?? "Logged in."
    }
}

/// The environment of the agent CLIs.
public enum AgentEnvironment {
    /// The variables that a CLI started from inside a Claude Code session inherits, and that change how a new session starts.
    static let dropped = ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT"]

    /// The agent nodes of the plugins use this config folder too, so the thread shares their login.
    public static func extra(_ provider: AgentProvider, home: String) -> [String: String] {
        provider == .claude ? ["CLAUDE_CONFIG_DIR": (home as NSString).appendingPathComponent(".claude")] : [:]
    }

    public static func full(_ provider: AgentProvider, home: String) -> [String: String] {
        var environment = ExecService.environment(home: home, extra: extra(provider, home: home))
        for name in dropped { environment[name] = nil }
        return environment
    }
}
