import AppKit
import Foundation
import Observation

/// Loads the plugins, runs them on their schedules and on card actions, and owns the stores that the views show.
@MainActor
@Observable
public final class PluginHost {
    public let paths: HostPaths
    public let board: BoardStore
    public let notes: NotesStore
    public let settings: SettingsStore
    public let notifications: NotificationStore
    public let pages: PageStore
    public let runs: RunStore
    public private(set) var plugins: [PluginEntry] = []
    /// The plugins with a run in progress.
    public private(set) var running: Set<String> = []
    /// The cards with an action in progress, as `plugin/card`, and the plugins with a menu action in progress, as `plugin`.
    public private(set) var pendingActions: Set<String> = []
    /// The answer to the last menu action of each plugin.
    public private(set) var pluginActionStatus: [String: String] = [:]
    /// Why the app could not set up the workspace of the threads, or nil.
    public private(set) var workspaceProblem: String?
    /// Shows a macOS notification. The app sets it, because a host in a test has no app bundle.
    public var deliver: @MainActor @Sendable (HostNotification) -> Void = { _ in }

    private let locks = LockService()
    private let browser = BrowserService()
    private var actionQueues: [String: Task<Void, Never>] = [:]
    /// The time of the run that each plugin asked for with runSoon.
    private var requestedRuns: [String: Date] = [:]
    static let soonDelayRange = 1_000...3_600_000
    private var lastCheck = Date()
    private var timer: Timer?
    private var watcher: FolderWatcher?
    private var asleep = false
    private let prelude: String

    public init(paths: HostPaths) {
        self.paths = paths
        board = BoardStore(dir: paths.file("board"))
        notes = NotesStore(url: paths.file("notes.json"))
        settings = SettingsStore(url: paths.file("settings.json"))
        notifications = NotificationStore(url: paths.file("notifications.json"))
        pages = PageStore(dir: paths.file("pages"))
        runs = RunStore(paths: paths)
        prelude = Prelude.source
        board.retentionDays = { [weak self] id in
            guard let self, let plugin = self.plugin(id) else { return DoneCards.defaultRetentionDays }
            return self.settings.retentionDays(plugin.manifest)
        }
    }

    // MARK: Lifecycle

    public func start() {
        installWorkspace()
        reload()
        watchUserPlugins()
        for plugin in plugins where plugin.manifest.runAtLaunch { runNow(plugin.id, trigger: "launch") }
        lastCheck = Date()
        // The timer also fires in a maintenance wake, which sleeps again within seconds. Only a full wake runs the missed slots.
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in if self?.asleep == false { self?.tick(now: Date()) } }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.asleep = true }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.asleep = false
                self?.tick(now: Date())
            }
        }
    }

    public func reload() {
        plugins = PluginCatalog.discover(in: paths.pluginDirs)
        for plugin in plugins {
            board.load(pluginId: plugin.id)
            pages.load(pluginId: plugin.id)
        }
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

    /// Starts each plugin with a slot in the time since the last check. After a sleep, a plugin runs once, as with launchd.
    public func tick(now: Date) {
        let after = lastCheck
        lastCheck = now
        for plugin in plugins { board.prune(pluginId: plugin.id) }
        for plugin in plugins where Schedule.isDue(plugin.manifest.schedule, after: after, until: now) {
            runNow(plugin.id, trigger: "schedule")
        }
    }

    /// Runs an action that another program asked for, and writes the answer to its reply file. It shows no dialog.
    public func performExternal(_ request: ExternalAction) {
        let reply = { (text: String) in
            guard let file = request.replyFile else { return }
            try? FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: URL(fileURLWithPath: file), options: .atomic)
        }
        guard let plugin = plugin(request.pluginId) else { return reply("Error: the plugin \(request.pluginId) does not exist") }
        if case .failure(let error) = request.check(plugin.manifest, repliesDir: paths.file("replies").path) { return reply("Error: \(error)") }
        performPluginAction(request.actionId, pluginId: request.pluginId, text: request.text) { result in
            switch result {
            case .success(let status): reply(status ?? "Done.")
            case .failure(let error): reply("Error: \(error)")
            }
        }
    }

    // MARK: Done cards

    public func retentionDays(_ id: String) -> Int {
        plugin(id).map { settings.retentionDays($0.manifest) } ?? DoneCards.defaultRetentionDays
    }

    public func setRetentionDays(_ days: Int, pluginId: String) {
        settings.setRetentionDays(days, pluginId: pluginId)
        board.prune(pluginId: pluginId)
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

    // MARK: Runs

    public func runNow(_ id: String, trigger: String = "manual") {
        guard let plugin = plugin(id) else { return }
        // A blocked plugin shows its reason on its page, so a slot does not add a record each time.
        if let blocker = blocker(id) {
            if trigger != "schedule" { skip(id, trigger: trigger, reason: blocker) }
            return
        }
        guard !running.contains(id) else { return skip(id, trigger: trigger, reason: "previous run still running") }
        running.insert(id)
        let record = runs.start(pluginId: id, kind: .run, trigger: trigger)
        let context = Reply.json(RunContext(settings: settings.resolved(plugin.manifest), trigger: trigger))
        Task {
            let result = await call(plugin, function: "run", arguments: [context], logFile: record.logFile)
            let (outcome, message) = Self.outcome(of: result)
            runs.finish(record.id, outcome: outcome, message: message)
            running.remove(id)
            // A run that a plugin asked for during this run starts now, if its time passed.
            if let at = requestedRuns[id], at <= Date() { startRequestedRun(id) }
        }
    }

    // MARK: Requested runs

    /// Keeps the earlier of two requests, so a batch of actions starts one run.
    public func requestRun(_ id: String, delayMs: Int) {
        let delay = min(max(delayMs, Self.soonDelayRange.lowerBound), Self.soonDelayRange.upperBound)
        let at = Date().addingTimeInterval(Double(delay) / 1000)
        if let current = requestedRuns[id], current <= at { return }
        requestedRuns[id] = at
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            self?.startRequestedRun(id)
        }
    }

    private func startRequestedRun(_ id: String) {
        guard let at = requestedRuns[id], at <= Date(), !running.contains(id) else { return }
        requestedRuns[id] = nil
        runNow(id, trigger: "soon")
    }

    private func skip(_ id: String, trigger: String, reason: String) {
        let record = runs.start(pluginId: id, kind: .run, trigger: trigger)
        let log = RunLog(path: record.logFile, pluginId: id)
        log.write("skipped: \(reason)")
        log.close()
        runs.finish(record.id, outcome: .skipped, message: reason)
    }

    // MARK: Actions

    /// The answer of an action: the status line of the plugin, or the reason that it failed.
    public typealias ActionFinished = @MainActor (Result<String?, HostError>) -> Void

    /// Finds an action in the manifest. A `cardId` asks for an item action of a stored item.
    public func resolveAction(pluginId: String, cardId: String?, actionId: String) -> Result<ResolvedAction, HostError> {
        guard let plugin = plugin(pluginId) else { return .failure(.failed("the plugin \(pluginId) does not exist")) }
        let card = cardId.flatMap { board.card(pluginId, $0) }
        return ActionLookup.resolve(actionId: actionId, cardId: cardId, pluginId: pluginId, manifest: plugin.manifest, card: card)
    }

    /// Runs a card action after the earlier actions of the same plugin. A run of the plugin does not block it.
    public func perform(_ actionId: String, cardId: String, pluginId: String, text: String? = nil, finished: @escaping ActionFinished = { _ in }) {
        let resolved = resolveAction(pluginId: pluginId, cardId: cardId, actionId: actionId)
        if case .failure(let error) = resolved.flatMap({ ActionLookup.checkText($0.action, text: text) }) { return finished(.failure(error)) }
        queueAction(
            pluginId: pluginId, key: "\(pluginId)/\(cardId)", trigger: "\(cardId):\(actionId)", function: "onAction",
            event: Reply.json(ActionEvent(cardId: cardId, actionId: actionId, text: text)),
            show: { [weak self] status in self?.board.setStatus(status, cardId: cardId, pluginId: pluginId) },
            finished: finished)
    }

    /// Runs an action of the plugin menu in the same queue as the card actions. The plugin page shows its answer.
    public func performPluginAction(_ actionId: String, pluginId: String, text: String? = nil, finished: @escaping ActionFinished = { _ in }) {
        let resolved = resolveAction(pluginId: pluginId, cardId: nil, actionId: actionId)
        if case .failure(let error) = resolved.flatMap({ ActionLookup.checkText($0.action, text: text) }) { return finished(.failure(error)) }
        queueAction(
            pluginId: pluginId, key: pluginId, trigger: actionId, function: "onPluginAction",
            event: Reply.json(PluginActionEvent(actionId: actionId, text: text)),
            show: { [weak self] status in self?.pluginActionStatus[pluginId] = status },
            finished: finished)
    }

    private func queueAction(
        pluginId: String, key: String, trigger: String, function: String, event: String,
        show: @escaping @MainActor (String?) -> Void, finished: @escaping ActionFinished
    ) {
        guard let plugin = plugin(pluginId) else { return finished(.failure(.failed("the plugin \(pluginId) does not exist"))) }
        if let problem = plugin.problem {
            show("Error: \(problem)")
            return finished(.failure(.failed(problem)))
        }
        pendingActions.insert(key)
        show("Working on it…")
        let context = Reply.json(RunContext(settings: settings.resolved(plugin.manifest), trigger: "action"))
        let previous = actionQueues[pluginId]
        actionQueues[pluginId] = Task {
            await previous?.value
            let record = runs.start(pluginId: pluginId, kind: .action, trigger: trigger)
            let result = await call(plugin, function: function, arguments: [event, context], logFile: record.logFile)
            let (outcome, message) = Self.outcome(of: result)
            runs.finish(record.id, outcome: outcome, message: message)
            pendingActions.remove(key)
            show(Self.status(of: result, outcome: outcome, message: message))
            finished(outcome == .failed ? .failure(.failed(message ?? "the action failed")) : .success(message))
        }
    }

    // MARK: Calls

    private func call(_ plugin: PluginEntry, function: String, arguments: [String], logFile: String) async -> Result<String?, HostError> {
        let log = RunLog(path: logFile, pluginId: plugin.id)
        let callId = UUID().uuidString
        let bridge = Bridge(
            pluginId: plugin.id, callId: callId, check: permissionCheck(plugin), info: info(plugin), log: log,
            services: HostServices(
                locks: locks, browser: browser, board: board, notes: notes, notifications: notifications, pages: pages,
                activity: { [weak self] reader, since in self?.activity(reader: reader, since: since) ?? Activity(notifications: [], cards: [], failedRuns: []) },
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
        Activity.since(
            since, reader: reader, names: Dictionary(plugins.map { ($0.id, $0.manifest.name) }, uniquingKeysWith: { first, _ in first }),
            cards: board.cards, notifications: notifications.items, runs: runs.records)
    }

    private func permissionCheck(_ plugin: PluginEntry) -> PermissionCheck {
        PermissionCheck(permissions: plugin.manifest.permissions, home: paths.home, alwaysAllowed: [paths.stateDir, plugin.dir, paths.dataDir])
    }

    private func info(_ plugin: PluginEntry) -> [String: String] {
        [
            "pluginId": plugin.id, "pluginDir": plugin.dir, "stateDir": paths.stateDir, "dataDir": paths.dataDir, "home": paths.home,
            "guardCommand": paths.guardCommand, "appCommand": paths.guardCommand, "timeZone": TimeZone.current.identifier,
        ]
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

    private static func status(of result: Result<String?, HostError>, outcome: RunRecord.Outcome, message: String?) -> String? {
        if outcome == .failed { return "Error: \(message ?? "the action failed")" }
        return message
    }
}

struct RunContext: Encodable {
    var settings: [String: String]
    var trigger: String
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
