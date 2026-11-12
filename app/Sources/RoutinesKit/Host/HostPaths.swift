import Foundation

/// The folders and files of the host. Tests pass their own.
public struct HostPaths: Sendable {
    public var home: String
    /// Shared by all plugins, so the state of the Bun routines carries over.
    public var stateDir: String
    public var dataDir: String
    public var pluginDirs: [String]
    /// The command that the Claude Code PreToolUse hook runs, with `--tool-guard`.
    public var guardCommand: String
    /// The folder that the app copies into the workspace: the agent rules, the SDK, the docs and the build script.
    public var workspaceSource: String?

    public init(home: String, stateDir: String, dataDir: String, pluginDirs: [String], guardCommand: String, workspaceSource: String? = nil) {
        self.home = home
        self.stateDir = stateDir
        self.dataDir = dataDir
        self.pluginDirs = pluginDirs
        self.guardCommand = guardCommand
        self.workspaceSource = workspaceSource
    }

    /// The folder where the coding agent of the threads works.
    public var workspaceDir: String { (dataDir as NSString).appendingPathComponent("workspace") }

    /// The routines that the agent makes. A plugin here replaces an installed plugin with the same id.
    public var workspacePluginsDir: String { (workspaceDir as NSString).appendingPathComponent("plugins") }

    /// The plugin folders that change while the app runs.
    public var userPluginDirs: [String] { pluginDirs.filter { $0.hasPrefix(dataDir + "/") } }

    /// The app ships no plugins. It loads them from Application Support, and during development also from `ROUTINES_PLUGINS_DIR`. `ROUTINES_DATA_DIR` and `ROUTINES_WORKSPACE_SOURCE` replace the data and workspace source folders.
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> HostPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dataDir = environment["ROUTINES_DATA_DIR"] ?? (home as NSString).appendingPathComponent("Library/Application Support/Routines")
        let development = environment["ROUTINES_PLUGINS_DIR"]
        let workspaceSource = environment["ROUTINES_WORKSPACE_SOURCE"] ?? Bundle.main.resourceURL?.appendingPathComponent("workspace").path
        var paths = HostPaths(
            home: home,
            stateDir: (home as NSString).appendingPathComponent(".local/state/routines"),
            dataDir: dataDir,
            pluginDirs: [],
            guardCommand: Bundle.main.executablePath ?? CommandLine.arguments[0],
            workspaceSource: workspaceSource
        )
        paths.pluginDirs = [development, (dataDir as NSString).appendingPathComponent("plugins"), paths.workspacePluginsDir].compactMap { $0 }
        return paths
    }

    public func file(_ name: String) -> URL {
        URL(fileURLWithPath: dataDir).appendingPathComponent(name)
    }

    public func runLogDir(pluginId: String) -> URL {
        file("runs").appendingPathComponent(pluginId)
    }
}
