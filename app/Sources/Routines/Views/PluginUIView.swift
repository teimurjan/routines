import AppKit
import RoutinesKit
import SwiftUI
import WebKit

/// The UI tab of a plugin. The web view stays hidden until the page sends `ready`, or for 1 second, so no white frame shows.
struct PluginUIView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    var plugin: PluginEntry
    @State private var controller: PluginUIController?
    @State private var accent = AccentColor.hex()

    var body: some View {
        let appearance = PluginUISnapshot.Appearance(scheme: colorScheme == .dark ? .dark : .light, accent: accent)
        ZStack {
            Theme.canvas
            if let controller {
                WebViewHost(controller: controller, snapshot: controller.snapshotJSON(appearance), appearance: appearance)
                    .opacity(controller.phase == .shown ? 1 : 0)
                if case .failed(let reason) = controller.phase {
                    ContentUnavailableView {
                        Label("The UI did not load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(reason)
                    } actions: {
                        Button("Reload") { Task { await controller.start() } }
                    }
                }
            }
        }
        .task(id: plugin.id) {
            let created = PluginUIController(plugin: plugin, host: model.host)
            controller = created
            takeFocus()
            await created.start()
        }
        .onChange(of: model.uiFocus) { takeFocus() }
        .onReceive(NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification)) { _ in accent = AccentColor.hex() }
    }

    /// The controller sends the item after `ready`, so a request from before the page loads still arrives.
    private func takeFocus() {
        guard let controller, let focus = model.uiFocus, focus.pluginId == plugin.id else { return }
        controller.focus(cardId: focus.card.id)
        model.uiFocus = nil
    }
}

/// Places the web view and sends each new snapshot to the page.
private struct WebViewHost: NSViewRepresentable {
    var controller: PluginUIController
    var snapshot: String
    var appearance: PluginUISnapshot.Appearance

    func makeNSView(context: Context) -> WKWebView { controller.web.webView }

    func updateNSView(_ view: WKWebView, context: Context) {
        controller.push(snapshot: snapshot, appearance: appearance)
    }
}

@MainActor
@Observable
final class PluginUIController {
    enum Phase: Equatable {
        case loading
        case shown
        case failed(String)
    }

    private(set) var phase = Phase.loading
    @ObservationIgnored let web: PluginWebView
    @ObservationIgnored private let pluginId: String
    @ObservationIgnored private let host: PluginHost
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var sent: String?
    @ObservationIgnored private var focusAfterReady: String?
    @ObservationIgnored private var appearance = PluginUISnapshot.Appearance(scheme: .light, accent: AccentColor.hex())

    init(plugin: PluginEntry, host: PluginHost) {
        pluginId = plugin.id
        self.host = host
        // The closures run on the main actor after init, so they reach the controller through a weak box.
        let box = WeakBox<PluginUIController>()
        web = PluginWebView(
            plugin: plugin, background: NSColor(Theme.canvas),
            listedImages: { PluginUIResources.listedImages(host.board.cards(of: plugin.id)) },
            respond: { body in await box.value?.respond(body) ?? .failure(.failed("the plugin UI closed")) })
        box.value = self
        web.onLoadError = { [weak self] reason in self?.phase = .failed(reason) }
    }

    /// Loads the page, then shows it after `ready` or after 1 second.
    func start() async {
        phase = .loading
        ready = false
        sent = nil
        await web.load()
        try? await Task.sleep(for: .seconds(1))
        if phase == .loading { show() }
    }

    func snapshotJSON(_ appearance: PluginUISnapshot.Appearance) -> String {
        host.uiSnapshot(pluginId: pluginId, appearance: appearance)?.json ?? "null"
    }

    func push(snapshot: String, appearance: PluginUISnapshot.Appearance) {
        self.appearance = appearance
        guard ready, snapshot != sent else { return }
        sent = snapshot
        Task { await web.send(type: "snapshot", valueJSON: snapshot) }
    }

    func focus(cardId: String) {
        guard ready else { return focusAfterReady = cardId }
        Task { await web.send(type: "focus", valueJSON: Self.focusJSON(cardId)) }
    }

    private func respond(_ body: Data) async -> Result<String, HostError> {
        guard let plugin = host.plugin(pluginId) else { return .failure(.failed("the plugin \(pluginId) is gone")) }
        let decision = PluginUIBridge(pluginId: pluginId).decide(
            body, manifest: plugin.manifest, card: { [host, pluginId] in host.board.card(pluginId, $0) }, snapshot: { snapshotJSON(appearance) })
        switch decision {
        case .reply(let json):
            sent = json
            return .success(json)
        case .ready:
            becomeReady()
            return .success("null")
        case .refuse(let reason): return .failure(.failed(reason))
        case .open(let url):
            NSWorkspace.shared.open(url)
            return .success("null")
        case .perform(let request): return await act(request, title: plugin.manifest.name)
        case .confirm(let request, let title): return await act(request, title: title)
        }
    }

    private func act(_ request: PluginUIAction, title: String) async -> Result<String, HostError> {
        await ActionGate.run(request, pluginId: pluginId, title: title, host: host).map(Self.statusJSON)
    }

    private func becomeReady() {
        ready = true
        show()
        // A change between the first snapshot and `ready` reaches the page here.
        push(snapshot: snapshotJSON(appearance), appearance: appearance)
        if let cardId = focusAfterReady {
            focusAfterReady = nil
            focus(cardId: cardId)
        }
    }

    private func show() {
        guard phase == .loading else { return }
        phase = .shown
        web.webView.window?.makeFirstResponder(web.webView)
    }

    private static func statusJSON(_ status: String?) -> String {
        (try? JSONEncoder().encode(status)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    private static func focusJSON(_ cardId: String) -> String {
        (try? JSONEncoder().encode(["cardId": cardId])).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }
}

@MainActor
private final class WeakBox<Value: AnyObject> {
    weak var value: Value?
}
