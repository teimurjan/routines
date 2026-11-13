import Foundation
@testable import RoutinesKit

enum Fixture {
    static var root: String { Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.path }
    static var plugins: String { (root as NSString).appendingPathComponent("plugins") }

    /// The test plugin with a UI, and the page that tries to break out of its web view.
    static var uiPlugin: PluginEntry { PluginCatalog.load(dir: (root as NSString).appendingPathComponent("ui-plugin"), folder: "ui-plugin") }
    static var hostilePlugin: PluginEntry { PluginCatalog.load(dir: (root as NSString).appendingPathComponent("hostile-ui"), folder: "hostile-ui") }

    /// A host that also loads the plugins with a UI.
    static func uiPaths() -> HostPaths {
        var paths = paths()
        paths.pluginDirs.append(root)
        return paths
    }

    static func paths() -> HostPaths {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("routines-tests-\(UUID().uuidString)").path
        return HostPaths(
            home: FileManager.default.homeDirectoryForCurrentUser.path,
            stateDir: root + "/state",
            dataDir: root + "/data",
            pluginDirs: [plugins],
            guardCommand: "/usr/bin/false")
    }
}

@MainActor
func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
}

extension Fixture {
    /// A host that loads only the routines and the source of `Fixtures/actionables`.
    static func actionablePaths() -> HostPaths {
        var paths = paths()
        paths.pluginDirs = [(root as NSString).appendingPathComponent("actionables")]
        return paths
    }
}

/// A clock that moves only when a test sets it.
final class FakeClock: @unchecked Sendable {
    private var current: Date
    private let lock = NSLock()

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = start
    }

    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }

    var function: @Sendable () -> Date { { self.now } }
}

/// Records each agent call and returns the queued answers in order. With no answer left, the call fails.
final class FakeAgent: @unchecked Sendable {
    struct Call {
        var args: [String]
        var stdin: String
    }

    private var answers: [Result<String, HostError>]
    private(set) var calls: [Call] = []
    private let lock = NSLock()

    init(_ answers: [Result<String, HostError>] = []) {
        self.answers = answers
    }

    func queue(_ answer: Result<String, HostError>) { lock.withLock { answers.append(answer) } }

    /// The JSON that `claude -p --output-format json` prints for a structured output.
    func queue(output: String) { queue(.success(#"{"is_error":false,"structured_output":\#(output)}"#)) }

    var count: Int { lock.withLock { calls.count } }

    var runner: AgentRunner {
        AgentRunner { args, stdin, _, _ in
            self.lock.withLock {
                self.calls.append(Call(args: args, stdin: stdin))
                return self.answers.isEmpty ? .failure(.failed("no answer queued")) : self.answers.removeFirst()
            }
        }
    }
}

extension PluginHost {
    /// A host on the fixtures of the actionables, with a fake clock and a fake agent.
    static func actionables(clock: FakeClock = FakeClock(), agent: FakeAgent = FakeAgent(), vault: AllowListVault = MemoryVault()) -> PluginHost {
        let host = PluginHost(paths: Fixture.actionablePaths(), now: clock.function, runAgent: agent.runner, vault: vault)
        host.reload()
        return host
    }

    /// Submits a trigger and waits for its answer.
    func answer(of trigger: Trigger) async -> Result<String?, HostError> {
        await withCheckedContinuation { continuation in
            submit(trigger) { continuation.resume(returning: $0) }
        }
    }

    /// A press of an item action of a plugin of today.
    func press(_ actionId: String, card cardId: String, of pluginId: String, text: String? = nil) async -> Result<String?, HostError> {
        guard let id = item(pluginId: pluginId, itemId: cardId)?.id else { return .failure(.failed("no card \(cardId)")) }
        return await answer(of: .transition(actionId, of: id, routine: pluginId, source: .ui, text: text, at: now()))
    }

    /// A press of a plugin action.
    func press(_ actionId: String, of pluginId: String, text: String? = nil) async -> Result<String?, HostError> {
        await answer(of: Trigger(routine: pluginId, source: .ui, work: .action, transition: actionId, text: text, at: now()))
    }

    /// A new actionable that a routine owns, as a source or a hand-off would make it.
    @discardableResult
    func seed(kind: String, owner: String?, state: Actionable.State = .new, key: String = UUID().uuidString, data: JSONValue = .object([:])) -> Actionable {
        try! actionables.create(
            kind: kind, source: "test", dedupeKey: key, owner: owner, state: state, title: "Item \(key.prefix(4))",
            step: Step.Draft(action: .created, actor: "test", trigger: "seed")
        ) { $0.data = data }.get()
    }
}
