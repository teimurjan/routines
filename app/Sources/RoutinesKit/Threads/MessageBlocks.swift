import Foundation

/// One block of an agent message. The inline Markdown of each text stays for the view.
public enum MessageBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case listItem(marker: String, depth: Int, text: String)
    case quote(String)
    /// A fence without its end, as a message shows while it streams, is still code.
    case code(language: String?, text: String)
    case rule
}

public enum MessageBlocks {
    private enum Line {
        case blank
        case fence(language: String?)
        case heading(level: Int, text: String)
        case rule
        case listItem(marker: String, depth: Int, text: String)
        case quote(String)
        case text(String)
    }

    public static func parse(_ text: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        var paragraph: [String] = []
        var code: (language: String?, lines: [String])?

        func flush() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }

        for raw in text.components(separatedBy: "\n") {
            let line = classify(raw)
            if let open = code {
                if case .fence = line {
                    blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n")))
                    code = nil
                } else {
                    code = (open.language, open.lines + [raw])
                }
                continue
            }
            switch line {
            case .text(let words):
                paragraph.append(words)
                continue
            case .quote(let words):
                flush()
                if case .quote(let previous) = blocks.last {
                    blocks[blocks.count - 1] = .quote(previous + "\n" + words)
                } else {
                    blocks.append(.quote(words))
                }
                continue
            default: flush()
            }
            switch line {
            case .fence(let language): code = (language, [])
            case .heading(let level, let words): blocks.append(.heading(level: level, text: words))
            case .rule: blocks.append(.rule)
            case .listItem(let marker, let depth, let words): blocks.append(.listItem(marker: marker, depth: depth, text: words))
            case .blank, .text, .quote: break
            }
        }
        flush()
        if let code { blocks.append(.code(language: code.language, text: code.lines.joined(separator: "\n"))) }
        return blocks
    }

    private static func classify(_ raw: String) -> Line {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .blank }
        if trimmed.hasPrefix("```") {
            let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return .fence(language: language.isEmpty ? nil : language)
        }
        if let match = trimmed.wholeMatch(of: /(#{1,6})\s+(.+)/) { return .heading(level: match.output.1.count, text: String(match.output.2)) }
        if trimmed.wholeMatch(of: /(-{3,}|\*{3,}|_{3,})/) != nil { return .rule }
        if let match = raw.wholeMatch(of: /(\s*)([-*+]|\d+[.)])\s+(.+)/) {
            let marker = String(match.output.2)
            return .listItem(marker: "-*+".contains(marker) ? "•" : marker, depth: match.output.1.count / 2, text: String(match.output.3))
        }
        if let match = trimmed.wholeMatch(of: />\s?(.*)/) { return .quote(String(match.output.1)) }
        return .text(raw)
    }
}
