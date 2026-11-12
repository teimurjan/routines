import Foundation

/// One CLI process of a turn. It hands each line of stdout to `onLine` while it runs, and it runs without a shell.
public final class AgentProcess: @unchecked Sendable {
    public struct Exit: Sendable {
        public var code: Int32
        /// The end of stderr, for the error of a turn that printed no result.
        public var stderr: String
        public var stopped: Bool
    }

    private let process = Process()
    private let lock = NSLock()
    private var wasStopped = false
    static let stderrLimit = 2000
    /// A child of the CLI can keep stdout open after the CLI ended, so the exit waits this long for the last lines.
    static let drainSeconds = 2.0
    static let killAfterSeconds = 3.0

    public init() {}

    public func run(
        _ cmd: [String], cwd: String, stdin: String, env: [String: String], home: String, onLine: @escaping @Sendable (String) -> Void
    ) async -> Result<Exit, HostError> {
        guard let name = cmd.first, let executable = ExecService.which(name, home: home) else {
            return .failure(.failed("\(cmd.first ?? ""): not found on the PATH"))
        }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(cmd.dropFirst())
        process.environment = env
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let stdout = Pipe()
        let stderr = Pipe()
        let input = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = input

        let exited = AsyncStream<Int32> { continuation in
            process.terminationHandler = { finished in
                continuation.yield(finished.terminationStatus)
                continuation.finish()
            }
        }
        do {
            try process.run()
        } catch {
            return .failure(.failed("\(name): \(error.localizedDescription)"))
        }
        let reader = Task.detached {
            for try await line in stdout.fileHandleForReading.bytes.lines { onLine(line) }
        }
        let errors = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }
        try? input.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
        try? input.fileHandleForWriting.close()

        var code: Int32 = -1
        for await status in exited { code = status }
        await Self.wait(for: { _ = await reader.result }, atMost: Self.drainSeconds)
        let errorData = await Self.wait(for: { await errors.value }, atMost: Self.drainSeconds) ?? Data()
        let text = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(Exit(code: code, stderr: String(text.suffix(Self.stderrLimit)), stopped: lock.withLock { wasStopped }))
    }

    /// The value of `work`, or nil after `seconds`. The work goes on in the background after a timeout.
    @discardableResult
    static func wait<Value: Sendable>(for work: @escaping @Sendable () async -> Value, atMost seconds: Double) async -> Value? {
        let first = AsyncStream<Value?> { continuation in
            Task.detached { continuation.yield(await work()) }
            Task.detached {
                try? await Task.sleep(for: .seconds(seconds))
                continuation.yield(nil)
            }
        }
        for await value in first { return value }
        return nil
    }

    /// Asks the CLI to end, and kills it if it does not end soon.
    public func stop() {
        lock.withLock { wasStopped = true }
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.killAfterSeconds) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}
