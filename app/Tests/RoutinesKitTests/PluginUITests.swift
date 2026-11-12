import Foundation
import Testing
@testable import RoutinesKit

private func decodeManifest(_ json: String) throws -> Manifest {
    try JSONDecoder().decode(Manifest.self, from: Data(json.utf8))
}

struct PluginUIManifestTests {
    @Test func aManifestActionCanAskFirst() throws {
        let manifest = try decodeManifest(#"{"id":"a","name":"A","actions":[{"id":"stop","label":"Stop","confirm":true},{"id":"go","label":"Go"}]}"#)
        #expect(manifest.actions.map(\.needsConfirmation) == [true, false])
    }
}

struct PluginUIResourcesTests {
    private let plugin = Fixture.uiPlugin

    private func resolve(_ url: String, listedImages: Set<String> = [], uiDir: String? = nil) -> PluginUIFile? {
        try? PluginUIResources.resolve(URL(string: url)!, pluginId: "ui-plugin", uiDir: uiDir ?? plugin.uiDir, listedImages: listedImages).get()
    }

    private func temporaryDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func theRootAndTheIndexServeTheIndex() {
        #expect(plugin.problem == nil)
        #expect(resolve("routines-ui://ui-plugin/")?.mimeType == "text/html")
        #expect(resolve("routines-ui://ui-plugin/index.html")?.path.hasSuffix("dist/ui/index.html") == true)
        #expect(resolve("routines-ui://ui-plugin/ui.js")?.mimeType == "text/javascript")
    }

    @Test func aNestedFileLoads() {
        #expect(resolve("routines-ui://ui-plugin/nested/extra.css")?.mimeType == "text/css")
    }

    @Test func aPathCannotLeaveTheUIFolder() {
        #expect(resolve("routines-ui://ui-plugin/../plugin.json") == nil)
        #expect(resolve("routines-ui://ui-plugin/%2E%2E/plugin.js") == nil)
        #expect(resolve("routines-ui://ui-plugin/nested/..%2F..%2Fplugin.js") == nil)
        #expect(resolve("routines-ui://ui-plugin/nested%2fextra.css") == nil)
    }

    @Test func aSymlinkCannotLeaveTheUIFolder() throws {
        let dir = try temporaryDir()
        try Data("<p>".utf8).write(to: dir.appendingPathComponent("index.html"))
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("hosts.css").path, withDestinationPath: "/etc/hosts")
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("up").path, withDestinationPath: Fixture.root)
        #expect(resolve("routines-ui://ui-plugin/index.html", uiDir: dir.path) != nil)
        #expect(resolve("routines-ui://ui-plugin/hosts.css", uiDir: dir.path) == nil)
        #expect(resolve("routines-ui://ui-plugin/up/ui-plugin/dist/ui/ui.js", uiDir: dir.path) == nil)
    }

    @Test func anotherHostOrSchemeIsRefused() {
        #expect(resolve("routines-ui://echo/index.html") == nil)
        #expect(resolve("file:///etc/hosts") == nil)
        #expect(resolve("https://ui-plugin/index.html") == nil)
    }

    @Test func anUnknownExtensionOrAMissingFileIsRefused() {
        #expect(resolve("routines-ui://ui-plugin/notes.txt") == nil)
        #expect(resolve("routines-ui://ui-plugin/missing.js") == nil)
        #expect(resolve("routines-ui://ui-plugin/nested") == nil)
    }

    @Test func onlyAnImageThatACardOfThePluginListsLoads() throws {
        let dir = try temporaryDir()
        let listed = dir.appendingPathComponent("a car.jpg").path
        let unlisted = dir.appendingPathComponent("other.jpg").path
        for path in [listed, unlisted] { try Data([0xFF, 0xD8]).write(to: URL(fileURLWithPath: path)) }
        let own = PluginUIResources.listedImages([Card(id: "a", title: "A", column: .needsYou, images: [listed])])
        let encoded = { (path: String) in "routines-ui://ui-plugin/_image/\(path.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)" }

        #expect(resolve(encoded(listed), listedImages: own)?.path == listed)
        #expect(resolve(encoded(unlisted), listedImages: own) == nil)
        // A path that only a card of another plugin lists is not in the set of this plugin.
        let foreign = PluginUIResources.listedImages([Card(id: "b", title: "B", column: .needsYou, images: [unlisted])])
        #expect(resolve(encoded(unlisted), listedImages: own.subtracting(foreign)) == nil)
        #expect(resolve(encoded("/etc/hosts"), listedImages: ["/etc/hosts"]) == nil)
    }
}

@MainActor
struct PluginUIBridgeTests {
    private let bridge = PluginUIBridge(pluginId: "ui-plugin")

    private func host() -> PluginHost {
        let host = PluginHost(paths: Fixture.uiPaths())
        host.reload()
        _ = host.board.upsert(Card(id: "c1", title: "First item", column: .needsYou), pluginId: "ui-plugin")
        _ = host.board.upsert(Card(id: "e1", title: "Echo item", column: .needsYou), pluginId: "echo")
        return host
    }

    private func decide(_ json: String, host: PluginHost? = nil) -> PluginUIDecision {
        let host = host ?? self.host()
        let manifest = host.plugin("ui-plugin")!.manifest
        let appearance = PluginUISnapshot.Appearance(scheme: .dark, accent: "#FF0000")
        return bridge.decide(
            Data(json.utf8), manifest: manifest, card: { host.board.card("ui-plugin", $0) },
            snapshot: { host.uiSnapshot(pluginId: "ui-plugin", appearance: appearance)!.json })
    }

    @Test func aSnapshotHoldsOnlyTheItemsOfItsPlugin() throws {
        guard case .reply(let json) = decide(#"{"type":"snapshot"}"#) else { Issue.record("no reply"); return }
        #expect(json.contains("First item"))
        #expect(!json.contains("Echo item"))
        #expect(json.contains(##""accent":"#FF0000""##))
        #expect(json.contains(#""scheme":"dark""#))
        #expect(json.contains(#""page":null"#))
        #expect(json.contains(#""label":"Wipe""#))
    }

    @Test func readyShowsThePage() {
        #expect(decide(#"{"type":"ready"}"#) == .ready)
    }

    @Test func onlyAnHTTPLinkOpens() {
        #expect(decide(#"{"type":"openLink","url":"https://example.com/lot/1"}"#) == .open(URL(string: "https://example.com/lot/1")!))
        #expect(decide(#"{"type":"openLink","url":"http://example.com"}"#) == .open(URL(string: "http://example.com")!))
        #expect(decide(#"{"type":"openLink","url":"file:///etc/hosts"}"#) == .refuse("only an http or https link opens"))
        #expect(decide(#"{"type":"openLink","url":"javascript:alert(1)"}"#) == .refuse("only an http or https link opens"))
    }

    @Test func aCardThatThePluginDoesNotHaveIsRefused() {
        #expect(decide(#"{"type":"perform","cardId":"missing","actionId":"open"}"#) == .refuse("denied: ui-plugin has no card missing"))
        // The card exists, but in another plugin.
        #expect(decide(#"{"type":"perform","cardId":"e1","actionId":"open"}"#) == .refuse("denied: ui-plugin has no card e1"))
    }

    @Test func anActionThatTheManifestDoesNotListIsRefused() {
        #expect(decide(#"{"type":"perform","cardId":"c1","actionId":"delete-all"}"#) == .refuse("denied: ui-plugin has no action delete-all"))
        #expect(decide(#"{"type":"performPluginAction","actionId":"delete-all"}"#) == .refuse("denied: ui-plugin has no action delete-all"))
    }

    @Test func anActionWithTheWrongTargetIsRefused() {
        #expect(decide(#"{"type":"perform","cardId":"c1","actionId":"refresh"}"#) == .refuse("denied: refresh is not an item action"))
        #expect(decide(#"{"type":"performPluginAction","actionId":"open"}"#) == .refuse("denied: open needs an item"))
    }

    @Test func aTextActionWithoutTextIsRefused() {
        #expect(decide(#"{"type":"perform","cardId":"c1","actionId":"reply"}"#) == .refuse("the action Reply needs text"))
        #expect(decide(#"{"type":"performPluginAction","actionId":"ask","text":" \n"}"#) == .refuse("the action Ask needs text"))
        let reply = CardAction(id: "reply", label: "Reply", input: CardAction.Input(placeholder: "text"), target: .item)
        #expect(decide(#"{"type":"perform","cardId":"c1","actionId":"reply","text":"yes"}"#) == .perform(PluginUIAction(action: reply, cardId: "c1", text: "yes")))
    }

    @Test func aMarkedActionAsksFirstWithTheStoredTitle() {
        let trash = CardAction(id: "trash", label: "Trash", style: .destructive, confirm: true, target: .item)
        // The message cannot turn the dialog off or rename the action: the decision uses the manifest action and the stored title.
        let message = #"{"type":"perform","cardId":"c1","actionId":"trash","confirm":false,"label":"Harmless","title":"Nothing"}"#
        #expect(decide(message) == .confirm(PluginUIAction(action: trash, cardId: "c1", text: nil), title: "First item"))
        let wipe = CardAction(id: "wipe", label: "Wipe", style: .destructive, confirm: true)
        #expect(decide(#"{"type":"performPluginAction","actionId":"wipe"}"#) == .confirm(PluginUIAction(action: wipe, cardId: nil, text: nil), title: "UI Plugin"))
    }

    @Test func aPlainActionRunsWithoutTheDialog() {
        let open = CardAction(id: "open", label: "Open", target: .item)
        #expect(decide(#"{"type":"perform","cardId":"c1","actionId":"open"}"#) == .perform(PluginUIAction(action: open, cardId: "c1", text: nil)))
        #expect(decide(#"{"type":"performPluginAction","actionId":"refresh"}"#) == .perform(PluginUIAction(action: CardAction(id: "refresh", label: "Refresh"), cardId: nil, text: nil)))
    }

    @Test func anUnknownTypeOrABadMessageIsRefused() {
        #expect(decide(#"{"type":"exec","cmd":["rm"]}"#) == .refuse("unknown message type exec"))
        #expect(decide(#""snapshot""#) == .refuse("the message must be an object with a type"))
    }
}
