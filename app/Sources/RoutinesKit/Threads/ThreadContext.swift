import Foundation

/// One loaded routine, as the agent sees it at the start of a turn.
public struct RoutineSummary: Equatable, Sendable {
    public enum Source: String, Sendable {
        case installed = "installed"
        case workspace = "workspace"
    }

    public var id: String
    public var name: String
    public var source: Source
    public var enabled: Bool
    public var problem: String?
    public var lastFailure: String?
}

/// The text that goes before your message in each turn, so the agent knows the current state of the app.
public enum ThreadContext {
    public static func prompt(_ message: String, workspace: String, dataDir: String, routines: [RoutineSummary]) -> String {
        let lines = routines.map { routine in
            var line = "- \(routine.id) (\(routine.name)): \(routine.source.rawValue), \(routine.enabled ? "on" : "off")."
            if let problem = routine.problem { line += " Problem: \(problem)." }
            if let failure = routine.lastFailure { line += " The last run failed: \(failure)" }
            return line
        }
        return """
            <routines-app>
            The Routines app sent this message. Your workspace is \(workspace), and AGENTS.md there has the rules.
            The data folder of the app is \(dataDir). The log of each run is in runs/<routine id>/ in that folder.
            The routines that the app loaded now:
            \(lines.isEmpty ? "None." : lines.joined(separator: "\n"))
            </routines-app>

            \(message)
            """
    }
}

extension PluginHost {
    public func routineSummaries() -> [RoutineSummary] {
        let workspacePlugins = paths.workspacePluginsDir + "/"
        return plugins.map { plugin in
            let lastRun = runs.records(of: plugin.id).first { $0.kind == .run && $0.outcome != .skipped && $0.outcome != .running }
            return RoutineSummary(
                id: plugin.id, name: plugin.manifest.name, source: plugin.dir.hasPrefix(workspacePlugins) ? .workspace : .installed,
                enabled: settings.isEnabled(plugin.id), problem: plugin.problem,
                lastFailure: lastRun?.outcome == .failed ? lastRun?.message ?? "no message" : nil)
        }
    }
}
