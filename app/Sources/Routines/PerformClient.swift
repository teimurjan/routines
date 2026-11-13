import AppKit
import RoutinesKit

enum PerformClient {
    static let timeout: TimeInterval = 120

    static let usage = "usage: Routines --perform <routine> <transition-or-action> [--item <id>] [text]\n"

    static func run(_ arguments: [String]) -> Int32 {
        guard let parsed = parse(arguments) else {
            FileHandle.standardError.write(Data(usage.utf8))
            return 64
        }
        let reply = HostPaths.standard().file("replies").appendingPathComponent("\(UUID().uuidString).txt")
        let request = ExternalAction(pluginId: parsed.routine, actionId: parsed.action, item: parsed.item, text: parsed.text, replyFile: reply.path)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(request.url, configuration: configuration)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let answer = try? String(contentsOf: reply, encoding: .utf8) {
                try? FileManager.default.removeItem(at: reply)
                print(answer)
                return answer.hasPrefix("Error") ? 1 : 0
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        FileHandle.standardError.write(Data("No answer from the Routines app after \(Int(timeout)) seconds.\n".utf8))
        return 1
    }

    /// `--item <id>` can stand anywhere after the action. The other words are the text.
    static func parse(_ arguments: [String]) -> (routine: String, action: String, item: String?, text: String?)? {
        guard arguments.count >= 2 else { return nil }
        var rest = Array(arguments.dropFirst(2))
        var item: String?
        if let index = rest.firstIndex(of: "--item") {
            guard index + 1 < rest.count else { return nil }
            item = rest[index + 1]
            rest.removeSubrange(index...(index + 1))
        }
        return (arguments[0], arguments[1], item, rest.isEmpty ? nil : rest.joined(separator: " "))
    }
}
