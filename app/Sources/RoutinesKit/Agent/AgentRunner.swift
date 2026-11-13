import Foundation

/// Runs one agent command and returns its stdout. The poll and the memory node use it, and tests pass a fake.
public struct AgentRunner: Sendable {
    public typealias Run = @Sendable (_ args: [String], _ stdin: String, _ cwd: String, _ timeout: Duration) async -> Result<String, HostError>

    private let run: Run

    public init(_ run: @escaping Run) {
        self.run = run
    }

    public func callAsFunction(_ args: [String], stdin: String, cwd: String, timeout: Duration) async -> Result<String, HostError> {
        await run(args, stdin, cwd, timeout)
    }

    /// The real CLI, without a shell. A run past its timeout stops and fails.
    public static func cli(home: String) -> AgentRunner {
        AgentRunner { args, stdin, cwd, timeout in
            let process = AgentProcess()
            let output = Lines()
            let watchdog = Task.detached {
                try? await Task.sleep(for: timeout)
                if !Task.isCancelled { process.stop() }
            }
            let exit = await process.run(args, cwd: cwd, stdin: stdin, env: AgentEnvironment.full(.claude, home: home), home: home) { output.append($0) }
            watchdog.cancel()
            return exit.flatMap { exit in
                if exit.stopped { return .failure(.failed("\(args.first ?? "agent"): timed out after \(timeout)")) }
                guard exit.code == 0 else { return .failure(.failed("\(args.first ?? "agent"): exit \(exit.code): \(exit.stderr)")) }
                return .success(output.text)
            }
        }
    }
}

private final class Lines: @unchecked Sendable {
    private var lines: [String] = []
    private let lock = NSLock()

    func append(_ line: String) { lock.withLock { lines.append(line) } }
    var text: String { lock.withLock { lines.joined(separator: "\n") } }
}

extension AgentRunner {
    /// The `structured_output` of the JSON that `claude -p --output-format json` prints.
    public static func structuredOutput(_ stdout: String) -> Result<JSONValue, HostError> {
        guard let data = stdout.data(using: .utf8), case .object(let result)? = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .failure(.failed("the agent printed no JSON result"))
        }
        if case .bool(true)? = result["is_error"] {
            if case .string(let text)? = result["result"] { return .failure(.failed(text)) }
            return .failure(.failed("the agent reported an error"))
        }
        guard let output = result["structured_output"], output != .null else { return .failure(.failed("the agent returned no structured output")) }
        return .success(output)
    }
}
