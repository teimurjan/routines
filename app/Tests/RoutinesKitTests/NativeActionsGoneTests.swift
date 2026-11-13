import Foundation
import Testing

/// Constitution R6: each press comes from a plugin UI and goes through the host gate, so the app draws no action control of its own.
/// Only the gate submits a trigger with the source `ui`.
struct NativeActionsGoneTests {
    private static let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Routines")
    private static let gate = "ActionGate.swift"
    private static let calls = ["source: .ui", "host.perform(", "host.performPluginAction("]
    private static let forbidden = [
        "ActionButtons", "ActionTextPrompt", "Menu(\"Actions\")", "BoardView", "ColumnView", "PluginPageView", "CardListView", "CardDetailView", "openCard",
        "InboxView", "InboxRow", "needsYou",
    ]

    private func sources() throws -> [(name: String, text: String)] {
        let files = FileManager.default.enumerator(at: Self.app, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    @Test func onlyTheGateSubmitsAPress() throws {
        let files = try sources()
        #expect(!files.isEmpty)
        for file in files where file.name != Self.gate {
            for call in Self.calls where file.text.contains(call) {
                Issue.record("\(file.name) uses \(call). Each press goes through ActionGate.")
            }
        }
    }

    @Test func theAppDrawsNoActionControl() throws {
        for file in try sources() {
            for name in Self.forbidden where file.text.contains(name) {
                Issue.record("\(file.name) still has \(name).")
            }
        }
    }
}
