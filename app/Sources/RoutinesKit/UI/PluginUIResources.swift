import Foundation

/// A file that the scheme handler can serve.
public struct PluginUIFile: Equatable, Sendable {
    public var path: String
    public var mimeType: String
}

/// The path rules of `routines-ui://<plugin id>/<path>`. See "Scheme resource" in specs/002-plugin-ui/data-model.md.
public enum PluginUIResources {
    public static let scheme = "routines-ui"
    static let imagePrefix = "/_image/"

    static let mimeTypes: [String: String] = [
        "html": "text/html", "js": "text/javascript", "css": "text/css", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "webp": "image/webp", "gif": "image/gif", "svg": "image/svg+xml", "woff2": "font/woff2",
    ]

    /// An encoded slash, backslash or NUL could hide a path part from the checks below.
    private static let hiddenSeparators = ["%2f", "%5c", "%00"]

    public static func indexURL(pluginId: String) -> URL {
        URL(string: "\(scheme)://\(pluginId)/index.html")!
    }

    /// The image paths that the stored cards of one plugin list.
    public static func listedImages(_ cards: [Card]) -> Set<String> {
        Set(cards.flatMap { $0.images ?? [] })
    }

    /// Maps a URL to a file of `uiDir`, or to an image that a card of the plugin lists. Every other URL is refused.
    public static func resolve(_ url: URL, pluginId: String, uiDir: String, listedImages: Set<String>) -> Result<PluginUIFile, HostError> {
        guard url.scheme == scheme, url.host() == pluginId else { return .failure(.denied("not a URL of \(pluginId): \(url.absoluteString)")) }
        let encoded = url.path(percentEncoded: true)
        if encoded.hasPrefix(imagePrefix) { return image(String(encoded.dropFirst(imagePrefix.count)), listedImages: listedImages) }
        return bundleFile(encoded, uiDir: uiDir)
    }

    private static func image(_ encoded: String, listedImages: Set<String>) -> Result<PluginUIFile, HostError> {
        guard let path = encoded.removingPercentEncoding, listedImages.contains(path) else { return .failure(.denied("no card lists the image")) }
        guard let mimeType = mimeType(of: path), mimeType.hasPrefix("image/") else { return .failure(.denied("not an image: \(path)")) }
        return isFile(path) ? .success(PluginUIFile(path: path, mimeType: mimeType)) : .failure(.denied("no such image: \(path)"))
    }

    private static func bundleFile(_ encoded: String, uiDir: String) -> Result<PluginUIFile, HostError> {
        let lowered = encoded.lowercased()
        if hiddenSeparators.contains(where: lowered.contains) { return .failure(.denied("an encoded separator in \(encoded)")) }
        guard let decoded = encoded.removingPercentEncoding else { return .failure(.denied("a bad path: \(encoded)")) }
        let relative = decoded.drop { $0 == "/" }
        let parts = (relative.isEmpty ? "index.html" : String(relative)).split(separator: "/", omittingEmptySubsequences: false)
        if parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) { return .failure(.denied("a bad path: \(decoded)")) }
        let root = URL(fileURLWithPath: uiDir).resolvingSymlinksInPath().path
        let file = URL(fileURLWithPath: root).appendingPathComponent(parts.joined(separator: "/")).resolvingSymlinksInPath().path
        guard file.hasPrefix(root + "/") else { return .failure(.denied("outside the UI folder: \(decoded)")) }
        guard let mimeType = mimeType(of: file) else { return .failure(.denied("a type that the UI cannot load: \(decoded)")) }
        return isFile(file) ? .success(PluginUIFile(path: file, mimeType: mimeType)) : .failure(.denied("no such file: \(decoded)"))
    }

    private static func mimeType(of path: String) -> String? {
        mimeTypes[(path as NSString).pathExtension.lowercased()]
    }

    private static func isFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}
