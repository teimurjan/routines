import Foundation
import Observation

public struct RunRecord: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case run, action }
    public enum Outcome: String, Codable, Sendable { case running, succeeded, failed, skipped }

    public var id: UUID
    public var pluginId: String
    public var kind: Kind
    public var trigger: String
    public var startedAt: Date
    public var endedAt: Date?
    public var outcome: Outcome
    public var message: String?
    public var logFile: String
}

/// The record of each run and action. Each one also writes a log file, so the improve plugin can audit them.
@MainActor
@Observable
public final class RunStore {
    public private(set) var records: [RunRecord] = []
    private let paths: HostPaths
    private let index: JSONFile<[RunRecord]>
    static let limit = 500

    public init(paths: HostPaths) {
        self.paths = paths
        index = JSONFile(url: paths.file("runs/index.json"))
        if case .success(let loaded) = index.load(default: []) {
            // A record that was running when the app quit did not end. Its last log line is the closest end time.
            records = loaded.map { record in
                guard record.endedAt == nil else { return record }
                var ended = record
                ended.outcome = .failed
                ended.message = "the app quit during the run"
                ended.endedAt = Self.lastWrite(record.logFile) ?? record.startedAt
                return ended
            }
        }
    }

    public func start(pluginId: String, kind: RunRecord.Kind, trigger: String) -> RunRecord {
        let startedAt = Date()
        let name = ISO8601.format(startedAt).replacingOccurrences(of: ":", with: "-") + (kind == .action ? "-action" : "") + ".log"
        let logFile = paths.runLogDir(pluginId: pluginId).appendingPathComponent(name).path
        let record = RunRecord(
            id: UUID(), pluginId: pluginId, kind: kind, trigger: trigger, startedAt: startedAt, endedAt: nil, outcome: .running, message: nil, logFile: logFile)
        records = Array(([record] + records).prefix(Self.limit))
        save()
        return record
    }

    public func finish(_ id: UUID, outcome: RunRecord.Outcome, message: String?) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].endedAt = Date()
        records[index].outcome = outcome
        records[index].message = message
        save()
    }

    public func records(of pluginId: String) -> [RunRecord] {
        records.filter { $0.pluginId == pluginId }
    }

    public func lastRun(of pluginId: String) -> RunRecord? {
        records.first { $0.pluginId == pluginId && $0.kind == .run && $0.outcome != .skipped }
    }

    private func save() {
        index.save(records)
    }

    private static func lastWrite(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}

/// Appends lines to the log file of one run. Any thread can call it.
public final class RunLog: @unchecked Sendable {
    private let handle: FileHandle?
    private let lock = NSLock()
    private let prefix: String

    public init(path: String, pluginId: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A daily log, such as the log of the polls, gets one more call.
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        prefix = pluginId
    }

    public func write(_ message: String) {
        let line = "\(ISO8601.format(Date())) \(message)\n"
        lock.withLock {
            _ = try? handle?.seekToEnd()
            try? handle?.write(contentsOf: Data(line.utf8))
        }
        print("[\(prefix)] \(message)")
    }

    public func close() {
        lock.withLock { try? handle?.close() }
    }

    public static func read(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
}
