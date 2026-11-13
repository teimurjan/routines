import Foundation

/// Pure checks of a call against the manifest of its plugin (constitution R3).
public struct PermissionCheck: Sendable {
    public let permissions: Permissions
    public let home: String
    /// Folders that each plugin can use: the shared state folder, its own folder and the app data folder.
    public let alwaysAllowed: [String]
    /// The host files in the data folder. A plugin reads them, but only the host writes them.
    public let protected: [String]

    public init(permissions: Permissions, home: String, alwaysAllowed: [String], protected: [String] = []) {
        self.permissions = permissions
        self.home = home
        self.alwaysAllowed = alwaysAllowed
        self.protected = protected
    }

    /// The files and folders of the data folder that the host owns.
    public static func hostFiles(dataDir: String) -> [String] {
        ["actionables", "memory", "decisions", "board", "sources", "settings.json"].map { (dataDir as NSString).appendingPathComponent($0) }
    }

    // `env` runs the command after its options and variables, so that command needs a permission too.
    public func command(_ cmd: [String]) -> Result<Void, HostError> {
        guard let first = cmd.first, !first.isEmpty else { return .failure(.denied("an empty command")) }
        let name = (first as NSString).lastPathComponent
        guard permissions.exec.contains(name) else { return .failure(.denied("the command \(name) is not in permissions.exec")) }
        guard name == "env" else { return .success(()) }
        var index = 1
        while index < cmd.count {
            let argument = cmd[index]
            // -S hides a command inside one string, so the check could not see it.
            if argument.hasPrefix("-S") || argument.hasPrefix("--split-string") { return .failure(.denied("env -S is not allowed")) }
            if ["-u", "-P", "-C"].contains(argument) {
                index += 2
            } else if argument.hasPrefix("-") || argument.contains("=") {
                index += 1
            } else {
                break
            }
        }
        return index < cmd.count ? command(Array(cmd[index...])) : .success(())
    }

    public func host(of urlString: String) -> Result<Void, HostError> {
        guard let host = URL(string: urlString)?.host()?.lowercased() else { return .failure(.denied("the URL \(urlString) has no host")) }
        let allowed = permissions.hosts.contains { pattern in
            let pattern = pattern.lowercased()
            // "*" is for a plugin that reads pages on any host, for example a link checker. The app shows it in the permissions.
            if pattern == "*" { return true }
            if pattern.hasPrefix("*.") { return host == String(pattern.dropFirst(2)) || host.hasSuffix(String(pattern.dropFirst(1))) }
            return host == pattern
        }
        return allowed ? .success(()) : .failure(.denied("the host \(host) is not in permissions.hosts"))
    }

    /// Returns the resolved path, so the caller uses the same path that the check saw.
    public func path(_ raw: String) -> Result<String, HostError> {
        let expanded = expand(raw)
        guard expanded.hasPrefix("/") else { return .failure(.denied("the path \(raw) is not absolute")) }
        let path = Self.resolve(expanded)
        let roots = (alwaysAllowed + permissions.paths.map(expand)).map(Self.resolve)
        let allowed = roots.contains { root in path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/") }
        return allowed ? .success(path) : .failure(.denied("the path \(raw) is not in permissions.paths"))
    }

    /// A path for a write. A host file and a path in a host folder are refused, and a delete also refuses a folder that holds one.
    public func writablePath(_ raw: String, removing: Bool = false) -> Result<String, HostError> {
        path(raw).flatMap { path in
            let inside = { (root: String) in path == root || path.hasPrefix(root + "/") || (removing && root.hasPrefix(path + "/")) }
            guard let owned = protected.map(Self.resolve).first(where: inside) else { return .success(path) }
            return .failure(.denied("the host owns \(owned)"))
        }
    }

    public func browser() -> Result<Void, HostError> {
        permissions.browser ? .success(()) : .failure(.denied("permissions.browser is not set"))
    }

    public func activity() -> Result<Void, HostError> {
        permissions.activity ? .success(()) : .failure(.denied("permissions.activity is not set"))
    }

    public func expand(_ path: String) -> String {
        if path == "~" { return home }
        return path.hasPrefix("~/") ? home + path.dropFirst(1) : path
    }

    /// Resolves `..` and the symbolic links of the longest part of the path that exists.
    static func resolve(_ path: String) -> String {
        let standard = (path as NSString).standardizingPath
        var existing = standard
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: existing), existing.hasPrefix("/"), existing != "/" {
            missing.insert((existing as NSString).lastPathComponent, at: 0)
            existing = (existing as NSString).deletingLastPathComponent
        }
        let resolved = URL(fileURLWithPath: existing).resolvingSymlinksInPath().path
        return missing.reduce(resolved) { ($0 as NSString).appendingPathComponent($1) }
    }
}

public enum HostError: Error, Equatable, Sendable, CustomStringConvertible {
    case denied(String)
    case failed(String)

    public var description: String {
        switch self {
        case .denied(let reason): "denied: \(reason)"
        case .failed(let reason): reason
        }
    }
}
