import Foundation

/// The Claude Code PreToolUse hook for a guarded tool. A call runs only if its input equals one of the inputs that the plugin chose.
public enum ToolGuard {
    public static let flag = "--tool-guard"

    public static func inputAllowed(_ input: [String: JSONValue], allowedInputs: [[String: JSONValue]]) -> Bool {
        allowedInputs.contains { allowed in input.count == allowed.count && allowed.allSatisfy { input[$0.key] == $0.value } }
    }

    /// Exit code 2 blocks the call. Any other failure must also block, so each error path returns 2.
    public static func run(stdin: Data, environment: [String: String]) -> (code: Int32, message: String?) {
        struct HookInput: Decodable { var tool_input: [String: JSONValue] }
        guard let hook = try? JSONDecoder().decode(HookInput.self, from: stdin) else { return (2, "Blocked: the guard could not read the tool call.") }
        let allowed = (try? JSONDecoder().decode([[String: JSONValue]].self, from: Data((environment["ROUTINES_TOOL_GUARD"] ?? "[]").utf8))) ?? []
        return inputAllowed(hook.tool_input, allowedInputs: allowed) ? (0, nil) : (2, "Blocked: this call is not one that the routine chose.")
    }
}
