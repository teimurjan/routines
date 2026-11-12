import Foundation

/// A plugin that the host found. A plugin with a `problem` shows in the sidebar but does not run.
public struct PluginEntry: Identifiable, Equatable, Sendable {
    public var manifest: Manifest
    public var dir: String
    public var problem: String?
    /// The change times of the bundle and the UI script, so a view can tell a new build.
    public var stamp: String = ""

    public var id: String { manifest.id }
    public var bundlePath: String { (dir as NSString).appendingPathComponent(manifest.main) }
    /// The built UI of the plugin. Only a manifest with `ui` uses it.
    public var uiDir: String { (dir as NSString).appendingPathComponent("dist/ui") }
}

public enum PluginCatalog {
    /// Reads each folder with a `plugin.json`. A later folder replaces a plugin with the same id, so the plugins of the workspace win.
    public static func discover(in roots: [String]) -> [PluginEntry] {
        var found: [String: PluginEntry] = [:]
        for root in roots {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            for name in names.sorted() {
                let dir = (root as NSString).appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("plugin.json")) else { continue }
                let entry = load(dir: dir, folder: name)
                found[entry.id] = entry
            }
        }
        return found.values.sorted { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }
    }

    public static func load(dir: String, folder: String) -> PluginEntry {
        let manifestURL = URL(fileURLWithPath: dir).appendingPathComponent("plugin.json")
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            return PluginEntry(manifest: Manifest(id: folder, name: folder), dir: dir, problem: "plugin.json: \(error)")
        }
        var entry = PluginEntry(manifest: manifest, dir: dir, problem: nil)
        entry.stamp = [entry.bundlePath, (entry.uiDir as NSString).appendingPathComponent("ui.js")].map(modified).joined(separator: "|")
        if manifest.id != folder { return with(entry, "the id \(manifest.id) does not match the folder \(folder)") }
        if !FileManager.default.fileExists(atPath: entry.bundlePath) { return with(entry, "\(manifest.main) is missing. Build the plugin again.") }
        return entry
    }

    private static func modified(_ path: String) -> String {
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        return date.map { String($0.timeIntervalSince1970) } ?? ""
    }

    private static func with(_ entry: PluginEntry, _ problem: String) -> PluginEntry {
        var broken = entry
        broken.problem = problem
        return broken
    }
}
