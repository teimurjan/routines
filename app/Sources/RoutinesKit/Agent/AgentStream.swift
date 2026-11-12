import Foundation

/// Turns one line of `--output-format stream-json` or `codex exec --json` output into thread events. A line that is not JSON gives none.
public enum AgentStream {
    /// A tool output longer than this keeps only its end, so a thread file stays small.
    static let outputLimit = 4000

    public static func parse(_ line: String, provider: AgentProvider, now: Date = Date()) -> [AgentEvent] {
        guard let data = line.data(using: .utf8), let event = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        switch provider {
        case .claude: return claude(event, now: now)
        case .codex: return codex(event, now: now)
        }
    }

    // MARK: Claude Code

    static func claude(_ event: JSONValue, now: Date) -> [AgentEvent] {
        switch event["type"]?.string {
        case "system":
            guard event["subtype"]?.string == "init", let id = event["session_id"]?.string else { return [] }
            return [.session(id)]
        case "assistant":
            return (event["message"]?["content"]?.array ?? []).compactMap { claudeBlock($0, now: now) }
        case "user":
            return (event["message"]?["content"]?.array ?? []).compactMap { block in
                guard block["type"]?.string == "tool_result", let id = block["tool_use_id"]?.string else { return nil }
                return .output(id: id, text: clip(claudeText(block["content"])), failed: block["is_error"]?.bool ?? false)
            }
        case "result":
            let failed = event["is_error"]?.bool ?? (event["subtype"]?.string != "success")
            let session = event["session_id"]?.string.map { [AgentEvent.session($0)] } ?? []
            return session + [.finished(error: failed ? (event["result"]?.string ?? "The agent failed.") : nil)]
        default:
            return []
        }
    }

    private static func claudeBlock(_ block: JSONValue, now: Date) -> AgentEvent? {
        switch block["type"]?.string {
        case "text":
            guard let text = block["text"]?.string, !text.isEmpty else { return nil }
            return .item(ThreadItem(kind: .message, text: text, date: now))
        case "tool_use":
            guard let id = block["id"]?.string, let name = block["name"]?.string else { return nil }
            let input = block["input"]
            let (kind, title) = claudeTool(name, input: input)
            return .item(ThreadItem(id: id, kind: kind, title: title, state: .running, date: now))
        default:
            return nil
        }
    }

    private static func claudeTool(_ name: String, input: JSONValue?) -> (ThreadItem.Kind, String) {
        switch name {
        case "Bash": return (.command, input?["command"]?.string ?? name)
        case "Write", "Edit", "MultiEdit", "NotebookEdit": return (.fileChange, input?["file_path"]?.string ?? input?["notebook_path"]?.string ?? name)
        default:
            let subject = ["file_path", "path", "pattern", "url", "query", "description"].lazy.compactMap { input?[$0]?.string }.first
            return (.tool, subject.map { "\(name) \($0)" } ?? name)
        }
    }

    /// A tool result is a string or a list of text blocks.
    private static func claudeText(_ content: JSONValue?) -> String {
        if let text = content?.string { return text }
        return (content?.array ?? []).compactMap { $0["text"]?.string }.joined(separator: "\n")
    }

    // MARK: Codex

    static func codex(_ event: JSONValue, now: Date) -> [AgentEvent] {
        switch event["type"]?.string {
        case "thread.started":
            return event["thread_id"]?.string.map { [.session($0)] } ?? []
        case "item.started", "item.updated", "item.completed":
            return event["item"].flatMap { codexItem($0, now: now) }.map { [.item($0)] } ?? []
        case "turn.completed":
            return [.finished(error: nil)]
        case "turn.failed":
            return [.finished(error: event["error"]?["message"]?.string ?? "The agent failed.")]
        case "error":
            // Codex also reports a retry of the connection this way, and the turn goes on.
            return event["message"]?.string.map { [.item(ThreadItem(kind: .error, text: $0, state: .failed, date: now))] } ?? []
        default:
            return []
        }
    }

    private static func codexItem(_ item: JSONValue, now: Date) -> ThreadItem? {
        guard let id = item["id"]?.string else { return nil }
        let state: ThreadItem.State = switch item["status"]?.string {
        case "in_progress": .running
        case "failed", "declined": .failed
        default: .done
        }
        switch item["type"]?.string {
        case "agent_message":
            return ThreadItem(id: id, kind: .message, text: item["text"]?.string ?? "", date: now)
        case "reasoning":
            return ThreadItem(id: id, kind: .reasoning, text: item["text"]?.string ?? "", date: now)
        case "command_execution":
            let exitCode = item["exit_code"]?.number
            let failed = state == .failed || (exitCode.map { $0 != 0 } ?? false)
            return ThreadItem(
                id: id, kind: .command, title: unwrapShell(item["command"]?.string ?? ""), text: clip(item["aggregated_output"]?.string ?? ""),
                state: failed ? .failed : state, date: now)
        case "file_change":
            let paths = (item["changes"]?.array ?? []).compactMap { $0["path"]?.string }
            return ThreadItem(id: id, kind: .fileChange, title: paths.joined(separator: ", "), state: state, date: now)
        case "mcp_tool_call":
            let name = [item["server"]?.string, item["tool"]?.string].compactMap { $0 }.joined(separator: ".")
            return ThreadItem(id: id, kind: .tool, title: name, state: state, date: now)
        case "web_search":
            return ThreadItem(id: id, kind: .tool, title: "Search \(item["query"]?.string ?? "")", state: state, date: now)
        case "error":
            return ThreadItem(id: id, kind: .error, text: item["message"]?.string ?? "", state: .failed, date: now)
        default:
            return nil
        }
    }

    /// Codex runs each command as `<shell> -lc '<command>'`. The thread shows the command only.
    static func unwrapShell(_ command: String) -> String {
        guard let match = command.wholeMatch(of: /\S+ -lc '(.*)'/.dotMatchesNewlines()) else { return command }
        return String(match.output.1)
    }

    static func clip(_ text: String) -> String {
        text.count > outputLimit ? "…" + String(text.suffix(outputLimit)) : text
    }
}

extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var bool: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var number: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var array: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
}
