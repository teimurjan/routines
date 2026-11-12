import Foundation
import Testing

/// The views take each color, font size and radius from design/tokens.json, through Tokens.swift and Theme.swift.
struct TokenUseTests {
    private static let views = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Routines/Views")
    private static let exempt: Set<String> = ["Tokens.swift", "Theme.swift"]
    private static let literals: [(name: String, pattern: String)] = [
        ("Color(light:", #"Color\(light:"#),
        ("a hex color", ##"0x[0-9A-Fa-f]{6,8}\b|"#[0-9A-Fa-f]{6}"##),
        (".system(size:) with a number", #"\.system\(size:\s*[0-9]"#),
        ("cornerRadius: with a number", #"cornerRadius:\s*[0-9]"#),
    ]

    @Test func theViewsUseNoStyleLiterals() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.views.path).filter { $0.hasSuffix(".swift") && !Self.exempt.contains($0) }
        #expect(!files.isEmpty)
        for file in files {
            let lines = try String(contentsOf: Self.views.appendingPathComponent(file), encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                for literal in Self.literals where line.range(of: literal.pattern, options: .regularExpression) != nil {
                    Issue.record("\(file):\(index + 1) uses \(literal.name). Take the value from Tokens or Theme.")
                }
            }
        }
    }
}
