import Foundation

/// Named locks that all plugins share. The host is one process, so a lock in memory replaces the lock files of the Bun routines.
public actor LockService {
    private var held: [String: String] = [:]
    private static let retry: Duration = .milliseconds(50)

    public init() {}

    public func acquire(_ name: String, owner: String, timeoutMs: Int) async -> Bool {
        let deadline = ContinuousClock.now + .milliseconds(timeoutMs)
        while held[name] != nil {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: Self.retry)
        }
        held[name] = owner
        return true
    }

    public func release(_ name: String, owner: String) {
        if held[name] == owner { held[name] = nil }
    }

    /// Frees the locks of a call that ended without a release, for example after a timeout.
    public func releaseAll(owner: String) {
        held = held.filter { $0.value != owner }
    }
}
