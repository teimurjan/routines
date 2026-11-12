import Foundation
import WebKit

/// Serves `routines-ui://<plugin id>/...` to the web view of one plugin, by the rules of `PluginUIResources`.
@MainActor
final class PluginUIScheme: NSObject, WKURLSchemeHandler {
    /// Inline script, remote files and every connection stay blocked. See specs/002-plugin-ui/research.md, section 3.
    static let contentPolicy =
        "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; connect-src 'none'; base-uri 'none'; form-action 'none'; frame-src 'none'"

    private let pluginId: String
    private let uiDir: String
    private let listedImages: @MainActor () -> Set<String>

    init(pluginId: String, uiDir: String, listedImages: @escaping @MainActor () -> Set<String>) {
        self.pluginId = pluginId
        self.uiDir = uiDir
        self.listedImages = listedImages
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        let resolved = PluginUIResources.resolve(url, pluginId: pluginId, uiDir: uiDir, listedImages: listedImages())
        let file = resolved.flatMap { file in
            Result { try Data(contentsOf: URL(fileURLWithPath: file.path)) }.map { (file.mimeType, $0) }.mapError { .failed($0.localizedDescription) }
        }
        switch file {
        case .success(let (mimeType, data)): respond(task, url: url, status: 200, mimeType: mimeType, body: data)
        case .failure: respond(task, url: url, status: 404, mimeType: "text/plain", body: Data())
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func respond(_ task: any WKURLSchemeTask, url: URL, status: Int, mimeType: String, body: Data) {
        let headers = ["Content-Type": mimeType, "Content-Length": "\(body.count)", "Content-Security-Policy": Self.contentPolicy, "Cache-Control": "no-store"]
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            return task.didFailWithError(URLError(.cannotParseResponse))
        }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }
}
