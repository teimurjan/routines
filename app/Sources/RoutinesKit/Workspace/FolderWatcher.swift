import CoreServices
import Foundation

/// Calls `onChange` on the main queue with the changed paths under the watched folders. FSEvents groups the changes of `latency` seconds.
public final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor ([String]) -> Void

    public init(paths: [String], latency: Double = 0.5, onChange: @escaping @MainActor ([String]) -> Void) {
        self.onChange = onChange
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
            MainActor.assumeIsolated { watcher.onChange(changed) }
        }
        stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    /// A change of a manifest, of a build, or of a whole plugin folder changes what the host loads. A source edit does not.
    public static func changesPlugins(_ path: String, roots: [String]) -> Bool {
        if path.hasSuffix("/plugin.json") || path.contains("/dist/") || path.hasSuffix("/dist") { return true }
        return roots.contains { root in (path as NSString).deletingLastPathComponent == root }
    }
}
