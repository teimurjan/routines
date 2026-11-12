import Foundation

public struct ExecRequest: Decodable, Sendable {
    public var cmd: [String]
    public var cwd: String?
    public var stdin: String?
    public var timeoutMs: Int?
    public var env: [String: String]?

    public init(cmd: [String], cwd: String? = nil, stdin: String? = nil, timeoutMs: Int? = nil, env: [String: String]? = nil) {
        self.cmd = cmd
        self.cwd = cwd
        self.stdin = stdin
        self.timeoutMs = timeoutMs
        self.env = env
    }
}

/// Runs a command without a shell, so text from a message cannot become a command.
public enum ExecService {
    /// An app started from Finder gets a short PATH, so the host adds the usual tool folders.
    public static func searchPath(home: String) -> [String] {
        ["\(home)/.local/bin", "\(home)/.bun/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    }

    public static func environment(home: String, extra: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath(home: home).joined(separator: ":")
        environment["HOME"] = home
        return environment.merging(extra) { _, new in new }
    }

    public static func which(_ name: String, home: String) -> String? {
        if name.contains("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        return searchPath(home: home)
            .map { ($0 as NSString).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Returns the trimmed stdout, or stderr as the error.
    public static func run(_ request: ExecRequest, home: String) async -> Result<String, HostError> {
        guard let name = request.cmd.first, let executable = which(name, home: home) else {
            return .failure(.failed("\(request.cmd.first ?? ""): not found on the PATH"))
        }
        let label = request.cmd.prefix(3).joined(separator: " ")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(request.cmd.dropFirst())
        process.environment = environment(home: home, extra: request.env ?? [:])
        if let cwd = request.cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let stdin = request.stdin.map { _ in Pipe() }
        process.standardInput = stdin ?? FileHandle.nullDevice

        let exited = AsyncStream<Int32> { continuation in
            process.terminationHandler = { finished in
                continuation.yield(finished.terminationStatus)
                continuation.finish()
            }
        }
        do {
            try process.run()
        } catch {
            return .failure(.failed("\(label): \(error.localizedDescription)"))
        }
        let output = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }
        let errors = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }
        if let stdin, let text = request.stdin {
            Task.detached {
                try? stdin.fileHandleForWriting.write(contentsOf: Data(text.utf8))
                try? stdin.fileHandleForWriting.close()
            }
        }

        let killed = TimeoutFlag()
        let watchdog = request.timeoutMs.map { ms in
            Task.detached {
                try await Task.sleep(for: .milliseconds(ms))
                killed.set()
                kill(process.processIdentifier, SIGKILL)
            }
        }
        var code: Int32 = -1
        for await status in exited { code = status }
        watchdog?.cancel()

        // A child of a killed process can keep the pipes open, so a timeout does not wait for them.
        if killed.isSet { return .failure(.failed("\(label): stopped by SIGKILL")) }
        let out = String(decoding: await output.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let err = String(decoding: await errors.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if code == 0 { return .success(out) }
        return .failure(.failed("\(label): \(err.isEmpty ? (out.isEmpty ? "exit \(code)" : out) : err)"))
    }
}

final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
