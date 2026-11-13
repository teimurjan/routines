import Foundation

/// One thing that the app learned from a step. It has no field that the policy reads (R8).
public struct MemoryEntry: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case answer, outcome, fact, preference
    }

    static let textLimit = 1000
    static let tagLimit = 8

    public var id: String
    public var type: Kind
    public var text: String
    public var tags: [String]
    /// The owner at the time of the step.
    public var routine: String
    public var step: String
    public var writtenAt: Date
    public var editedAt: Date?

    public init(id: String = UUID().uuidString, type: Kind, text: String, tags: [String], routine: String, step: String, writtenAt: Date, editedAt: Date? = nil) {
        self.id = id
        self.type = type
        self.text = text
        self.tags = tags
        self.routine = routine
        self.step = step
        self.writtenAt = writtenAt
        self.editedAt = editedAt
    }

    /// The actionable of the step, as the step id is `<actionable>.<number>`.
    public var actionable: String { String(step.split(separator: ".").first ?? "") }

    public var changedAt: Date { editedAt ?? writtenAt }

    /// Text has 1 to 1,000 characters, and tags are at most 8, lowercase.
    static func check(text: String, tags: [String]) -> Result<(String, [String]), HostError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...textLimit).contains(trimmed.count) else { return .failure(.failed("the text of an entry has 1 to 1,000 characters")) }
        let cleaned = tags.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        guard cleaned.count <= tagLimit else { return .failure(.failed("an entry has at most 8 tags")) }
        return .success((trimmed, cleaned))
    }
}
