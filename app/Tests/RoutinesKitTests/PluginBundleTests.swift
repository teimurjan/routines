import Foundation
import Testing
@testable import RoutinesKit

/// Each built plugin in `ROUTINES_PLUGINS_DIR` must evaluate in JavaScriptCore and register itself. Nothing runs, so no plugin acts.
@MainActor
struct PluginBundleTests {
    nonisolated static let pluginsDir = ProcessInfo.processInfo.environment["ROUTINES_PLUGINS_DIR"]

    @Test(.enabled(if: pluginsDir != nil, "ROUTINES_PLUGINS_DIR is not set"))
    func everyBuiltPluginLoadsInJavaScriptCore() async throws {
        let entries = PluginCatalog.discover(in: [Self.pluginsDir ?? ""])
        for entry in entries { #expect(entry.problem == nil, "\(entry.id): \(entry.problem ?? "")") }
        let paths = Fixture.paths()
        let prelude = Prelude.source
        for entry in entries where entry.problem == nil {
            let log = RunLog(path: paths.dataDir + "/\(entry.id).log", pluginId: entry.id)
            let services = HostServices(
                locks: LockService(), browser: BrowserService(),
                notes: NotesStore(url: URL(fileURLWithPath: paths.dataDir + "/notes.json")),
                notifications: NotificationStore(url: URL(fileURLWithPath: paths.dataDir + "/n.json")),
                pages: PageStore(dir: URL(fileURLWithPath: paths.dataDir + "/pages")),
                activity: { _, _ in Activity(notifications: [], cards: [], failedRuns: []) }, deliver: { _ in })
            let bridge = Bridge(
                pluginId: entry.id, callId: "test", check: PermissionCheck(permissions: Permissions(), home: paths.home, alwaysAllowed: []),
                info: ["pluginId": entry.id, "home": paths.home, "stateDir": paths.stateDir, "dataDir": paths.dataDir, "pluginDir": entry.dir, "guardCommand": "/usr/bin/false", "timeZone": "UTC"],
                log: log, services: services)
            let bundle = try String(contentsOfFile: entry.bundlePath, encoding: .utf8)
            let loaded = await PluginRuntime(bridge: bridge).load(prelude: prelude, bundle: bundle, bundleURL: URL(fileURLWithPath: entry.bundlePath))
            #expect((try? loaded.get()) != nil, "\(entry.id): \(loaded)")
        }
        #expect(!entries.isEmpty)
    }
}
