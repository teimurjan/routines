import AppKit
import CryptoKit
import Foundation
import WebKit

/// Off-screen WebKit pages for plugins with `permissions.browser`. A profile keeps its cookies between runs, so a passed Cloudflare check stays passed.
@MainActor
public final class BrowserService {
    private struct Session {
        let owner: String
        let view: WKWebView
        let window: NSWindow
        let navigation: NavigationWaiter
    }

    private var sessions: [String: Session] = [:]
    private static let poll: Duration = .milliseconds(250)

    public init() {}

    /// The `owner` is the call that holds the session. The store comes from the plugin, so it outlives the call.
    public func open(profile: String, pluginId: String, owner: String) -> String {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.storeId(pluginId: pluginId, profile: profile))
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 900), configuration: configuration)
        // A page in a window that is not on screen still runs its scripts and timers like a visible page.
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 1280, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderBack(nil)
        let navigation = NavigationWaiter()
        view.navigationDelegate = navigation
        let id = UUID().uuidString
        sessions[id] = Session(owner: owner, view: view, window: window, navigation: navigation)
        return id
    }

    public func goto(session id: String, url: String, timeoutMs: Int, owner: String) async -> Result<Void, HostError> {
        guard let session = sessions[id], session.owner == owner else { return .failure(.failed("no browser session \(id)")) }
        guard let target = URL(string: url) else { return .failure(.failed("invalid URL \(url)")) }
        session.navigation.reset()
        session.view.load(URLRequest(url: target))
        let deadline = ContinuousClock.now + .milliseconds(timeoutMs)
        while ContinuousClock.now < deadline {
            if let outcome = session.navigation.outcome { return outcome }
            try? await Task.sleep(for: Self.poll)
        }
        return .failure(.failed("timed out loading \(url)"))
    }

    public func waitFor(session id: String, expression: String, timeoutMs: Int, owner: String) async -> Result<Bool, HostError> {
        guard let session = sessions[id], session.owner == owner else { return .failure(.failed("no browser session \(id)")) }
        let deadline = ContinuousClock.now + .milliseconds(timeoutMs)
        while ContinuousClock.now < deadline {
            if (try? await session.view.evaluateJavaScript("Boolean(\(expression))")) as? Bool == true { return .success(true) }
            try? await Task.sleep(for: Self.poll)
        }
        return .success(false)
    }

    /// Returns the JSON text of the value that the async function body returns.
    public func evaluate(session id: String, body: String, argumentsJSON: String, owner: String) async -> Result<String, HostError> {
        guard let session = sessions[id], session.owner == owner else { return .failure(.failed("no browser session \(id)")) }
        let wrapped = "const __args = \(argumentsJSON); const __value = await (async ({ \(Self.argumentNames(argumentsJSON)) }) => { \(body) })(__args); return JSON.stringify(__value === undefined ? null : __value);"
        do {
            let value = try await session.view.callAsyncJavaScript(wrapped, arguments: [:], in: nil, contentWorld: .page)
            return .success((value as? String) ?? "null")
        } catch {
            return .failure(.failed("browser: \(error.localizedDescription)"))
        }
    }

    public func close(session id: String, owner: String) {
        guard let session = sessions[id], session.owner == owner else { return }
        session.window.orderOut(nil)
        session.view.navigationDelegate = nil
        sessions[id] = nil
    }

    public func closeAll(owner: String) {
        for (id, session) in sessions where session.owner == owner { close(session: id, owner: session.owner) }
    }

    private static func argumentNames(_ json: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return "" }
        return object.keys.filter { $0.range(of: "^[A-Za-z_$][A-Za-z0-9_$]*$", options: .regularExpression) != nil }.joined(separator: ", ")
    }

    // The same plugin and profile always get the same store, so cookies persist across app launches.
    nonisolated static func storeId(pluginId: String, profile: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data("\(pluginId)/\(profile)".utf8)))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    var outcome: Result<Void, HostError>?

    func reset() { outcome = nil }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        outcome = .success(())
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        outcome = .failure(.failed(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        outcome = .failure(.failed(error.localizedDescription))
    }
}
