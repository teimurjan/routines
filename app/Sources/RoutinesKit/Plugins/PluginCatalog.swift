import Foundation

/// A plugin that the host found. A plugin with a `problem` shows in the sidebar but does not run.
public struct PluginEntry: Identifiable, Equatable, Sendable {
    public var manifest: Manifest
    public var dir: String
    public var problem: String?
    /// The change times of the bundle and the UI script, so a view can tell a new build.
    public var stamp: String = ""
    /// The schema of each kind that the manifest declares, from `dist/kinds.json`.
    public var kinds: [String: KindSchema] = [:]

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
        if let problem = ManifestRules.problem(manifest) { return with(entry, problem) }
        switch kinds(of: manifest, dir: dir) {
        case .success(let kinds): entry.kinds = kinds
        case .failure(let error): return with(entry, error.description)
        }
        return entry
    }

    /// Each declared kind needs a schema that the host can check.
    static func kinds(of manifest: Manifest, dir: String) -> Result<[String: KindSchema], HostError> {
        guard !manifest.kinds.isEmpty else { return .success([:]) }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("dist/kinds.json")
        guard let data = try? Data(contentsOf: url) else { return .failure(.failed("dist/kinds.json is missing. Build the plugin again.")) }
        guard case .object(let schemas)? = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .failure(.failed("dist/kinds.json must be an object of schemas"))
        }
        var kinds: [String: KindSchema] = [:]
        for kind in manifest.kinds {
            guard let schema = schemas[kind] else { return .failure(.failed("dist/kinds.json has no schema for the kind \(kind)")) }
            switch KindSchema.parse(schema, path: "the schema of \(kind)") {
            case .success(let parsed): kinds[kind] = parsed
            case .failure(let error): return .failure(error)
            }
        }
        return .success(kinds)
    }

    static func modified(_ path: String) -> String {
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        return date.map { String($0.timeIntervalSince1970) } ?? ""
    }

    private static func with(_ entry: PluginEntry, _ problem: String) -> PluginEntry {
        var broken = entry
        broken.problem = problem
        return broken
    }
}

/// The rules of a manifest that one manifest alone can break. See "Manifest" in specs/004-actionables/contracts/actionables.md.
enum ManifestRules {
    static func problem(_ manifest: Manifest) -> String? {
        if manifest.source != nil, !manifest.handles.isEmpty || !manifest.transitions.isEmpty {
            return "a source cannot have handles or transitions"
        }
        if let kind = (manifest.kinds + manifest.handles.map(\.kind) + (manifest.source?.kinds ?? [])).first(where: { !isKindName($0) }) {
            return "the kind \(kind) must have only lowercase letters, digits and -"
        }
        if let empty = manifest.transitions.first(where: { $0.from.isEmpty }) { return "the transition \(empty.id) starts from no state" }
        let ids = manifest.transitions.map(\.id) + manifest.actions.map(\.id)
        if let repeated = ids.first(where: { id in ids.count { $0 == id } > 1 }) { return "the id \(repeated) is used twice in transitions and actions" }
        if let tool = manifest.source?.tools.first(where: { !$0.hasPrefix("mcp__") }) { return "the source tool \(tool) must start with mcp__" }
        return nil
    }

    static func isKindName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }
}
