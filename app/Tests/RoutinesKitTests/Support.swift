import Foundation
@testable import RoutinesKit

enum Fixture {
    static var root: String { Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.path }
    static var plugins: String { (root as NSString).appendingPathComponent("plugins") }

    /// The test plugin with a UI, and the page that tries to break out of its web view.
    static var uiPlugin: PluginEntry { PluginCatalog.load(dir: (root as NSString).appendingPathComponent("ui-plugin"), folder: "ui-plugin") }
    static var hostilePlugin: PluginEntry { PluginCatalog.load(dir: (root as NSString).appendingPathComponent("hostile-ui"), folder: "hostile-ui") }

    /// A host that also loads the plugins with a UI.
    static func uiPaths() -> HostPaths {
        var paths = paths()
        paths.pluginDirs.append(root)
        return paths
    }

    static func paths() -> HostPaths {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("routines-tests-\(UUID().uuidString)").path
        return HostPaths(
            home: FileManager.default.homeDirectoryForCurrentUser.path,
            stateDir: root + "/state",
            dataDir: root + "/data",
            pluginDirs: [plugins],
            guardCommand: "/usr/bin/false")
    }
}

@MainActor
func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
}
