import Foundation

/// One JSON line per decision in `decisions/<yyyy-mm-dd>.jsonl`, for 14 days. See specs/004-actionables/research.md, section 7.
@MainActor
public final class DecisionLog {
    public struct Record: Codable, Equatable, Sendable {
        public var id: String
        public var at: Date
        public var trigger: Trigger
        public var decision: String
        public var reason: String?
    }

    static let keptDays = 14
    private let dir: URL
    /// The last refusal of each blocked routine, so an equal refusal adds no line.
    private var lastBlocked: [String: String] = [:]

    public init(dir: URL) {
        self.dir = dir
    }

    /// Returns false when it skipped an equal refusal of a blocked routine.
    @discardableResult
    public func record(_ trigger: Trigger, _ decision: Decision) -> Bool {
        if case .refuse(.blocked(let reason)) = decision {
            if lastBlocked[trigger.routine] == reason { return false }
            lastBlocked[trigger.routine] = reason
        } else {
            lastBlocked[trigger.routine] = nil
        }
        let record = Record(id: trigger.id, at: trigger.at, trigger: trigger, decision: decision.name, reason: decision.refusal?.description)
        append(Reply.json(record) + "\n", to: file(for: trigger.at))
        return true
    }

    public func records(on day: Date) -> [Record] {
        let text = (try? String(contentsOf: file(for: day), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { try? Reply.decoder.decode(Record.self, from: Data($0.utf8)) }
    }

    /// Deletes the files of days before the kept days.
    public func prune(now: Date) {
        let cutoff = Self.day(now.addingTimeInterval(-Double(Self.keptDays) * 24 * 60 * 60))
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names where name.hasSuffix(".jsonl") && String(name.dropLast(6)) < cutoff {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    private func file(for date: Date) -> URL {
        dir.appendingPathComponent("\(Self.day(date)).jsonl")
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func append(_ line: String, to url: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
        try? handle.close()
    }
}
