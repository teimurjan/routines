import Foundation

/// The ranking of the memory search tool. See "The search tool" in specs/004-actionables/contracts/memory.md.
public enum MemorySearch {
    public static let maxEntries = 8
    public static let maxCharacters = 4000

    /// Each query word in the text adds 1, and each matching tag adds 2. Equal scores put the newer entry first, and a score of 0 does not show.
    public static func search(_ entries: [MemoryEntry], routine: String, query: String, tags: [String] = [], limit: Int = maxEntries) -> [MemoryEntry] {
        let words = Set(Self.words(query))
        let wanted = Set(tags.map { $0.lowercased() }).union(words)
        let scored = entries.filter { $0.routine == routine }.compactMap { entry -> (MemoryEntry, Int)? in
            let text = Set(Self.words(entry.text))
            let score = words.intersection(text).count + 2 * Set(entry.tags).intersection(wanted).count
            return score > 0 ? (entry, score) : nil
        }
        let ranked = scored.sorted { ($0.1, $0.0.changedAt) > ($1.1, $1.0.changedAt) }.map(\.0)
        var size = 0
        var kept: [MemoryEntry] = []
        for entry in ranked.prefix(min(max(limit, 1), maxEntries)) {
            size += entry.text.count
            if size > maxCharacters { break }
            kept.append(entry)
        }
        return kept
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
