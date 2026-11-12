import Foundation

/// The folder where the coding agent makes and changes routines. The app owns each top-level entry of the source, and the agent owns `plugins/`.
public enum Workspace {
    static let versionFile = "version.txt"
    static let agentOwned = "plugins"

    /// Replaces the app-owned entries when the source has a new version. It never touches `plugins/`.
    public static func install(from source: String, into dir: String) -> Result<Bool, HostError> {
        let files = FileManager.default
        let version = try? String(contentsOfFile: (source as NSString).appendingPathComponent(versionFile), encoding: .utf8)
        guard let version else { return .failure(.failed("\(source) has no \(versionFile). Run bun run build.")) }
        let installed = try? String(contentsOfFile: (dir as NSString).appendingPathComponent(versionFile), encoding: .utf8)
        do {
            try files.createDirectory(atPath: (dir as NSString).appendingPathComponent(agentOwned), withIntermediateDirectories: true)
            if installed == version { return .success(false) }
            for name in try files.contentsOfDirectory(atPath: source) where name != agentOwned && name != versionFile {
                let target = (dir as NSString).appendingPathComponent(name)
                if files.fileExists(atPath: target) { try files.removeItem(atPath: target) }
                try files.copyItem(atPath: (source as NSString).appendingPathComponent(name), toPath: target)
            }
            // The version goes last, so a failed copy runs again at the next launch.
            try version.write(toFile: (dir as NSString).appendingPathComponent(versionFile), atomically: true, encoding: .utf8)
            return .success(true)
        } catch {
            return .failure(.failed("workspace: \(error.localizedDescription)"))
        }
    }
}
