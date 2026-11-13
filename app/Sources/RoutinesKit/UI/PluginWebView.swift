import AppKit
import Foundation
import WebKit

/// The web view of one plugin UI, with the four layers of specs/002-plugin-ui/research.md, section 3.
@MainActor
public final class PluginWebView: NSObject {
    /// Answers one message of the page with the JSON of a value, or with the reason of a refusal.
    public typealias Respond = @MainActor (Data) async -> Result<String, HostError>

    static let messageHandler = "routines"
    private static let ruleListId = "routines-ui-only"
    // Each load outside the scheme is blocked, including loads that the content policy does not name.
    private static let rules = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}},{"trigger":{"url-filter":"^routines-ui://"},"action":{"type":"ignore-previous-rules"}}]"#
    private static var ruleList: WKContentRuleList?
    private static let hostWorld = WKContentWorld.world(name: "routines-host")

    public let webView: WKWebView
    public let pluginId: String
    private let indexURL: URL
    private let uiDir: String
    private let respond: Respond
    private var navigated = false
    /// The page did not load, with the reason.
    public var onLoadError: @MainActor (String) -> Void = { _ in }
    /// You Command-clicked the item with this id. The id is one that `setCardIds` gave.
    public var onAsk: @MainActor (String) -> Void = { _ in }

    public init(plugin: PluginEntry, background: NSColor, listedImages: @escaping @MainActor () -> Set<String>, respond: @escaping Respond) {
        pluginId = plugin.id
        uiDir = plugin.uiDir
        indexURL = PluginUIResources.indexURL(pluginId: plugin.id)
        self.respond = respond
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(
            PluginUIScheme(pluginId: plugin.id, uiDir: plugin.uiDir, listedImages: listedImages), forURLScheme: PluginUIResources.scheme)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = background
        webView.allowsLinkPreview = false
        super.init()
        let controller = configuration.userContentController
        controller.addScriptMessageHandler(WeakHandler(self), contentWorld: .page, name: Self.messageHandler)
        controller.addUserScript(WKUserScript(source: AskScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.hostWorld))
        controller.add(WeakAskHandler(self), contentWorld: Self.hostWorld, name: AskScript.handler)
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    /// Loads the index of the plugin after the rule list is in place. Without the rule list the page does not load.
    public func load() async {
        guard FileManager.default.fileExists(atPath: (uiDir as NSString).appendingPathComponent("index.html")) else {
            return onLoadError("dist/ui/index.html is missing. Build the plugin again.")
        }
        switch await Self.compiledRuleList() {
        case .failure(let error): onLoadError("The content rules did not compile: \(error)")
        case .success(let list):
            let controller = webView.configuration.userContentController
            controller.removeAllContentRuleLists()
            controller.add(list)
            navigated = false
            webView.load(URLRequest(url: indexURL))
        }
    }

    /// Dispatches a `routines` event on `window`. The value goes in as an argument, so no text of an item becomes script.
    public func send(type: String, valueJSON: String) async {
        guard let value = try? JSONSerialization.jsonObject(with: Data(valueJSON.utf8), options: .fragmentsAllowed) else { return }
        _ = try? await webView.callAsyncJavaScript(
            "window.dispatchEvent(new CustomEvent('routines', { detail: event }))", arguments: ["event": ["type": type, "value": value]], in: nil,
            contentWorld: .page)
    }

    /// The items that a Command-click can ask about. Only the host world sees them.
    public func setCardIds(_ ids: [String]) async {
        _ = try? await webView.callAsyncJavaScript("window.routinesCards = new Set(ids)", arguments: ["ids": ids], in: nil, contentWorld: Self.hostWorld)
    }

    private static func compiledRuleList() async -> Result<WKContentRuleList, HostError> {
        if let ruleList { return .success(ruleList) }
        guard let store = WKContentRuleListStore.default() else { return .failure(.failed("no content rule store")) }
        do {
            guard let list = try await store.compileContentRuleList(forIdentifier: ruleListId, encodedContentRuleList: rules) else {
                return .failure(.failed("an empty rule list"))
            }
            ruleList = list
            return .success(list)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    fileprivate func receive(_ message: WKScriptMessage) async -> Any {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, origin.protocol == PluginUIResources.scheme, origin.host == pluginId else {
            return Self.envelope(.failure(.denied("a message from another frame")))
        }
        guard let body = try? JSONSerialization.data(withJSONObject: message.body, options: .fragmentsAllowed) else {
            return Self.envelope(.failure(.failed("the message is not JSON")))
        }
        return Self.envelope(await respond(body))
    }

    fileprivate func ask(_ message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, origin.protocol == PluginUIResources.scheme, origin.host == pluginId,
            let cardId = (message.body as? [String: Any])?["cardId"] as? String
        else { return }
        onAsk(cardId)
    }

    /// The promise of the page resolves with `{ ok: true, value }` or `{ ok: false, error }`.
    private static func envelope(_ result: Result<String, HostError>) -> Any {
        switch result {
        case .success(let json):
            let value = (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)) ?? NSNull()
            return ["ok": true, "value": value]
        case .failure(let error): return ["ok": false, "error": error.description]
        }
    }
}

extension PluginWebView: WKNavigationDelegate, WKUIDelegate {
    /// Only the first load of the index in the main frame. A link goes through `openLink`.
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard !navigated, navigationAction.targetFrame?.isMainFrame == true, navigationAction.request.url == indexURL else { return .cancel }
        navigated = true
        return .allow
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        onLoadError(error.localizedDescription)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        onLoadError(error.localizedDescription)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onLoadError("The page stopped.")
    }

    /// `window.open` returns null.
    public func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }
}

/// The content controller keeps its handlers, so the handler holds the web view weakly.
@MainActor
private final class WeakHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var target: PluginWebView?

    init(_ target: PluginWebView) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let target else { return (nil, "the plugin UI closed") }
        return (await target.receive(message), nil)
    }
}

@MainActor
private final class WeakAskHandler: NSObject, WKScriptMessageHandler {
    weak var target: PluginWebView?

    init(_ target: PluginWebView) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.ask(message)
    }
}
