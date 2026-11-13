import AppKit
import Foundation
import Observation

/// Loads the plugins, runs them through one entrance, and owns the stores that the views show.
@MainActor
@Observable
public final class PluginHost {
    public let paths: HostPaths
    public let actionables: ActionableStore
    public let notes: NotesStore
    public let settings: SettingsStore
    public let notifications: NotificationStore
    public let pages: PageStore
    public let runs: RunStore
    public let decisions: DecisionLog
    public let allowList: AllowList
    public let cursors: CursorStore
    public let memory: MemoryStore
    public private(set) var plugins: [PluginEntry] = []
    /// Which routine handles each kind and state.
    public private(set) var handles = HandlesTable.empty
    /// The run lifecycle of each routine. A missing routine is idle.
    public internal(set) var lifecycles: [String: RunLifecycle] = [:]
    /// The actionables with a transition in progress, as `plugin/item`, and the plugins with a plugin action in progress, as `plugin`.
    public internal(set) var pendingActions: Set<String> = []
    /// The answer to the last plugin action of each plugin.
    public internal(set) var pluginActionStatus: [String: String] = [:]
    /// Why the app could not set up the workspace of the threads, or nil.
    public private(set) var workspaceProblem: String?
    /// Shows a macOS notification. The app sets it, because a host in a test has no app bundle.
    public var deliver: @MainActor @Sendable (HostNotification) -> Void = { _ in }

    let now: @Sendable () -> Date
    let runAgent: AgentRunner
    let locks = LockService()
    let browser = BrowserService()
    var actionQueues: [String: Task<Void, Never>] = [:]
    /// The trigger of the run that follows the current run of each routine.
    var queuedRuns: [String: Trigger] = [:]
    @ObservationIgnored var poller: Poller?
    @ObservationIgnored var memoryRunning = false
    static let soonDelayRange = 1_000...3_600_000
    private var lastCheck = Date()
    private var timer: Timer?
    private var watcher: FolderWatcher?
    var isAsleep = false
    private let prelude: String

    /// The app passes the Keychain vault. Tests keep the allow list in memory.
    public init(
        paths: HostPaths, now: @escaping @Sendable () -> Date = Date.init, runAgent: AgentRunner? = nil, vault: AllowListVault = MemoryVault()
    ) {
        self.paths = paths
        self.now = now
        self.runAgent = runAgent ?? .cli(home: paths.home)
        actionables = ActionableStore(dir: paths.file("actionables"), now: now)
        notes = NotesStore(url: paths.file("notes.json"))
        settings = SettingsStore(url: paths.file("settings.json"))
        notifications = NotificationStore(url: paths.file("notifications.json"))
        pages = PageStore(dir: paths.file("pages"))
        runs = RunStore(paths: paths)
        decisions = DecisionLog(dir: paths.file("decisions"))
        allowList = AllowList(vault: vault)
        cursors = CursorStore(dir: paths.file("sources"))
        memory = MemoryStore(dir: paths.file("memory"), now: now)
        prelude = Prelude.source
        actionables.retentionDays = { [weak self] owner in
            guard let self, let owner, let plugin = self.plugin(owner) else { return DoneCards.defaultRetentionDays }
            return self.settings.retentionDays(plugin.manifest)
        }
        actionables.onStep = { [weak self] actionable, step in self?.stepAdded(step, of: actionable) }
    }

    /// The plugins with a run in progress.
    public var running: Set<String> { Set(lifecycles.filter { $0.value != .idle }.keys) }

    /// The board calls of the plugins of today.
    public var boardAdapter: BoardAdapter { BoardAdapter(store: actionables) }

    // MARK: Lifecycle

    public func start() {
        installWorkspace()
        reload()
        Migration.run(boardDir: paths.file("board"), store: actionables)
        decisions.prune(now: now())
        watchUserPlugins()
        for plugin in plugins where plugin.manifest.runAtLaunch { submit(.run(plugin.id, source: .clock, at: now())) }
        lastCheck = Date()
        startPolling()
        startMemory()
        // The timer also fires in a maintenance wake, which sleeps again within seconds. Only a full wake runs the missed slots.
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in if self?.isAsleep == false { self?.tick(now: Date()) } }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isAsleep = true }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isAsleep = false
                self?.tick(now: Date())
            }
        }
    }

    /// Loads the plugins, then refuses the plugins whose kinds or handles another plugin already has (FR-009).
    public func reload() {
        let found = PluginCatalog.discover(in: paths.pluginDirs)
        let built = Handles.build(found)
        plugins = found.map { entry in
            guard let problem = built.problems[entry.id] else { return entry }
            var refused = entry
            refused.problem = problem
            return refused
        }
        handles = built
        for plugin in plugins { pages.load(pluginId: plugin.id) }
    }

    private func installWorkspace() {
        guard let source = paths.workspaceSource else { return }
        if case .failure(let error) = Workspace.install(from: source, into: paths.workspaceDir) { workspaceProblem = error.description }
    }

    /// A plugin that the agent builds, copies or deletes shows in the sidebar at once.
    private func watchUserPlugins() {
        let roots = paths.userPluginDirs
        for root in roots { try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true) }
        watcher = FolderWatcher(paths: roots) { [weak self] changed in
            if changed.contains(where: { FolderWatcher.changesPlugins($0, roots: roots) }) { self?.reload() }
        }
    }

    /// Submits a clock trigger for each plugin with a slot in the time since the last check. After a sleep, a plugin runs once, as with launchd.
    public func tick(now date: Date) {
        let after = lastCheck
        lastCheck = date
        actionables.prune()
        for plugin in plugins where Schedule.isDue(plugin.manifest.schedule, after: after, until: date) {
            submit(.run(plugin.id, source: .clock, at: now()))
        }
        poller?.tick(now: date)
    }

    /// Asks for a run with the source `self` after the delay.
    public func requestRun(_ id: String, delayMs: Int) {
        let delay = min(max(delayMs, Self.soonDelayRange.lowerBound), Self.soonDelayRange.upperBound)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard let self else { return }
            self.submit(.run(id, source: .selfRequest, at: self.now()))
        }
    }

    // MARK: Done actionables

    public func retentionDays(_ id: String) -> Int {
        plugin(id).map { settings.retentionDays($0.manifest) } ?? DoneCards.defaultRetentionDays
    }

    public func setRetentionDays(_ days: Int, pluginId: String) {
        settings.setRetentionDays(days, pluginId: pluginId)
        actionables.prune()
    }

    public func plugin(_ id: String) -> PluginEntry? {
        plugins.first { $0.id == id }
    }

    /// Why a plugin cannot run now, or nil.
    public func blocker(_ id: String) -> String? {
        guard let plugin = plugin(id) else { return "the plugin \(id) does not exist" }
        if let problem = plugin.problem { return problem }
        if !settings.isEnabled(id) { return "the plugin is off" }
        let missing = settings.missing(plugin.manifest)
        if !missing.isEmpty { return "missing settings: \(missing.map(\.label).joined(separator: ", "))" }
        return nil
    }

    // MARK: Calls

    func call(_ plugin: PluginEntry, function: String, arguments: [String], logFile: String, trigger: String) async -> Result<String?, HostError> {
        let log = RunLog(path: logFile, pluginId: plugin.id)
        let callId = UUID().uuidString
        let bridge = Bridge(
            pluginId: plugin.id, callId: callId, trigger: trigger, check: permissionCheck(plugin), info: info(plugin), log: log,
            services: HostServices(
                locks: locks, browser: browser, notes: notes, notifications: notifications, pages: pages,
                activity: { [weak self] reader, since in self?.activity(reader: reader, since: since) ?? Activity(notifications: [], cards: [], failedRuns: []) },
                actionables: { [weak self] pluginId, trigger, request in
                    self?.handle(request, pluginId: pluginId, trigger: trigger) ?? .failure(.failed("the app quit"))
                },
                deliver: deliver, runLater: { [weak self] id, delayMs in self?.requestRun(id, delayMs: delayMs) }))
        let runtime = PluginRuntime(bridge: bridge)
        let bundle = (try? String(contentsOfFile: plugin.bundlePath, encoding: .utf8)) ?? ""
        log.write("\(function) started")
        let loaded = await runtime.load(prelude: prelude, bundle: bundle, bundleURL: URL(fileURLWithPath: plugin.bundlePath))
        let result: Result<String?, HostError>
        switch loaded {
        case .failure(let error): result = .failure(error)
        case .success: result = await runtime.call(function, arguments: arguments, timeout: Double(plugin.manifest.timeoutMinutes) * 60)
        }
        await locks.releaseAll(owner: callId)
        browser.closeAll(owner: callId)
        switch result {
        case .success(let value): log.write("\(function) ended: \(value?.prefix(300) ?? "no function")")
        case .failure(let error): log.write("\(function) failed: \(error)")
        }
        log.close()
        return result
    }

    private func activity(reader: String, since: Date) -> Activity {
        let cards = Dictionary(grouping: actionables.all.filter { $0.owner != nil }, by: { $0.owner! }).mapValues { list in list.map { $0.card(id: $0.id) } }
        return Activity.since(
            since, reader: reader, names: Dictionary(plugins.map { ($0.id, $0.manifest.name) }, uniquingKeysWith: { first, _ in first }),
            cards: cards, notifications: notifications.items, runs: runs.records)
    }

    private func permissionCheck(_ plugin: PluginEntry) -> PermissionCheck {
        PermissionCheck(
            permissions: plugin.manifest.permissions, home: paths.home, alwaysAllowed: [paths.stateDir, plugin.dir, paths.dataDir],
            protected: PermissionCheck.hostFiles(dataDir: paths.dataDir))
    }

    private func info(_ plugin: PluginEntry) -> [String: String] {
        [
            "pluginId": plugin.id, "pluginDir": plugin.dir, "stateDir": paths.stateDir, "dataDir": paths.dataDir, "home": paths.home,
            "guardCommand": paths.guardCommand, "appCommand": paths.guardCommand, "timeZone": TimeZone.current.identifier,
        ]
    }

    func context(_ plugin: PluginEntry, trigger: Trigger) -> String {
        Reply.json(
            RunContext(
                settings: settings.resolved(plugin.manifest), trigger: trigger.legacyName, source: trigger.source.rawValue, actionable: trigger.actionable))
    }

    /// A value `{ ok: false, error }` from the plugin counts as a failure, the same as a thrown error.
    static func outcome(of result: Result<String?, HostError>) -> (RunRecord.Outcome, String?) {
        switch result {
        case .failure(let error): return (.failed, error.description)
        case .success(let json):
            guard let json, let value = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)), case .object(let object) = value,
                case .bool(let ok)? = object["ok"]
            else { return (.succeeded, nil) }
            if ok, case .string(let text)? = object["value"] { return (.succeeded, text) }
            if !ok, case .string(let error)? = object["error"] { return (.failed, error) }
            return (ok ? .succeeded : .failed, nil)
        }
    }
}

struct RunContext: Encodable {
    var settings: [String: String]
    /// The string of today: clock is "schedule", self is "soon", ui is "action".
    var trigger: String
    var source: String
    var actionable: String?
}

struct ActionEvent: Encodable {
    var cardId: String
    var actionId: String
    var text: String?
}

struct PluginActionEvent: Encodable {
    var actionId: String
    var text: String?
}
