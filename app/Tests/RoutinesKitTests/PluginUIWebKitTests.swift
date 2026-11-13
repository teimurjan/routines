import AppKit
import Foundation
import Testing
@testable import RoutinesKit

/// Loads a hostile page in a real web view. It needs a window server, so it runs only with ROUTINES_WEBKIT_TESTS=1.
@MainActor
struct PluginUIWebKitTests {
    private struct Report: Decodable {
        var type: String
        var name: String
        var blocked: Bool
    }

    @MainActor
    private final class Reports {
        var blocked: [String: Bool] = [:]
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ROUTINES_WEBKIT_TESTS"] == "1"))
    func aHostilePageFailsAtEachTry() async throws {
        let host = PluginHost(paths: Fixture.uiPaths())
        host.reload()
        let plugin = try #require(host.plugin("hostile-ui"))
        host.boardAdapter.upsert(Card(id: "h1", title: "Hostile", column: .needsYou), pluginId: plugin.id, trigger: "test")
        let reports = Reports()
        let bridge = PluginUIBridge(pluginId: plugin.id)
        let web = PluginWebView(plugin: plugin, background: .windowBackgroundColor, listedImages: { [] }) { body in
            if let report = try? JSONDecoder().decode(Report.self, from: body), report.type == "report" {
                reports.blocked[report.name] = report.blocked
                return .success("null")
            }
            switch bridge.decide(body, manifest: plugin.manifest, card: { host.boardAdapter.card(plugin.id, $0) }, snapshot: { "null" }) {
            case .refuse(let reason): return .failure(.failed(reason))
            default: return .success("null")
            }
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = web.webView
        await web.load()
        await waitUntil(timeout: .seconds(20)) { reports.blocked["done"] != nil }

        for name in ["inline script", "remote script", "fetch", "navigation", "file link", "other plugin", "unlisted action"] {
            #expect(reports.blocked[name] == true, "the page was not stopped at: \(name)")
        }
        #expect(web.webView.url?.scheme == PluginUIResources.scheme)
    }
}
