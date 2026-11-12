import Foundation

/// The command line of one thread turn. The prompt goes on stdin, and each CLI prints one JSON event per line.
public enum AgentCommand {
    /// Auto mode judges each tool call, so a turn needs nobody at the Mac.
    public static func claude(_ config: AgentConfig, sessionId: String?, mcpConfig: String?) -> [String] {
        var args = [
            AgentProvider.claude.executable, "-p", "--output-format", "stream-json", "--verbose",
            "--permission-mode", "auto",
        ]
        if let mcpConfig { args += ["--mcp-config", mcpConfig] }
        if let model = config.modelName { args += ["--model", model] }
        if let effort = config.effort { args += ["--effort", effort.rawValue] }
        if let sessionId { args += ["--resume", sessionId] }
        return args
    }

    /// The workspace-write sandbox lets Codex write only in its working folder.
    public static func codex(_ config: AgentConfig, sessionId: String?) -> [String] {
        var options = ["--json", "--skip-git-repo-check", "-c", #"sandbox_mode="workspace-write""#]
        if let model = config.modelName { options += ["-m", model] }
        if let effort = config.effort { options += ["-c", "model_reasoning_effort=\"\(effort.rawValue)\""] }
        let head = [AgentProvider.codex.executable, "exec"]
        guard let sessionId else { return head + options + ["-"] }
        return head + [CodexSubcommand.resume.rawValue] + options + [sessionId, "-"]
    }
}

enum CodexSubcommand: String {
    case resume
}
