import AppKit
import RoutinesKit

enum PerformClient {
    static let timeout: TimeInterval = 120

    static func run(_ arguments: [String]) -> Int32 {
        guard arguments.count >= 2 else {
            FileHandle.standardError.write(Data("usage: Routines --perform <plugin> <action> [text]\n".utf8))
            return 64
        }
        let reply = HostPaths.standard().file("replies").appendingPathComponent("\(UUID().uuidString).txt")
        let text = arguments.count > 2 ? arguments[2...].joined(separator: " ") : nil
        let request = ExternalAction(pluginId: arguments[0], actionId: arguments[1], text: text, replyFile: reply.path)
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
}
