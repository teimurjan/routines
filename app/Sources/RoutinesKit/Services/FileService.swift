import Foundation

public struct FileEntry: Codable, Equatable, Sendable {
    public var name: String
    public var isDirectory: Bool
    public var modifiedAt: String
}

/// File calls on paths that `PermissionCheck.path` already resolved.
public enum FileService {
    private static var manager: FileManager { .default }

    public static func exists(_ path: String) -> Bool {
        manager.fileExists(atPath: path)
    }

    public static func readText(_ path: String) -> Result<String, HostError> {
        attempt { try String(contentsOfFile: path, encoding: .utf8) }
    }

    public static func readBase64(_ path: String) -> Result<String, HostError> {
        attempt { try Data(contentsOf: URL(fileURLWithPath: path)).base64EncodedString() }
    }

    public static func write(_ data: Data, to path: String, mode: Int? = nil) -> Result<Void, HostError> {
        attempt {
            let url = URL(fileURLWithPath: path)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            if let mode { try manager.setAttributes([.posixPermissions: mode], ofItemAtPath: path) }
        }
    }

    public static func remove(_ path: String) -> Result<Void, HostError> {
        guard exists(path) else { return .success(()) }
        return attempt { try manager.removeItem(atPath: path) }
    }

    public static func mkdir(_ path: String) -> Result<Void, HostError> {
        attempt { try manager.createDirectory(atPath: path, withIntermediateDirectories: true) }
    }

    public static func list(_ path: String) -> Result<[FileEntry], HostError> {
        attempt {
            let url = URL(fileURLWithPath: path)
            let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
            return try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys).map { item in
                let values = try item.resourceValues(forKeys: Set(keys))
                return FileEntry(
                    name: item.lastPathComponent,
                    isDirectory: values.isDirectory ?? false,
                    modifiedAt: ISO8601.format(values.contentModificationDate ?? .distantPast)
                )
            }
        }
    }

    private static func attempt<T>(_ work: () throws -> T) -> Result<T, HostError> {
        do {
            return .success(try work())
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }
}
