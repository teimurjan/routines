import RoutinesKit
import ServiceManagement
import SwiftUI
import UserNotifications

enum SidebarItem: Hashable {
    case runs
    case memory
    case plugin(String)
}

/// The routine thread in the thread panel: one routine, or the actionables with no owner.
enum RoutineSelection: Hashable {
    case routine(String)
    case noOwner

    var routine: String? {
        if case .routine(let id) = self { return id }
        return nil
    }
}

/// An item that a plugin UI shows once its page is ready.
struct UIFocus: Equatable {
    var pluginId: String
    var itemId: String
}

enum PluginTab: String, Identifiable {
    case ui = "UI"
    case runs = "Runs"
    case settings = "Settings"

    var id: String { rawValue }

    /// The UI of the plugin, when it ships one, then Runs and Settings, which each plugin has.
    static func tabs(of manifest: Manifest) -> [PluginTab] {
        (manifest.ui == nil ? [] : [.ui]) + [.runs, .settings]
    }

    /// The UI tab takes its label from the manifest.
    func label(in manifest: Manifest) -> String {
        self == .ui ? manifest.ui?.title ?? rawValue : rawValue
    }
}

/// What you typed in a thread and did not send yet, with the items that you added to it.
struct ThreadDraft: Equatable {
    var text = ""
    var references: [ItemReference] = []
}

enum ThreadPage: Equatable {
    case conversation
    case list
}

@MainActor
@Observable
final class AppModel: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppModel(host: PluginHost(paths: .standard(), vault: KeychainVault()))
    let host: PluginHost
    let threads: ThreadService
    var selectedThread: String?
    /// The routine thread that the panel shows instead of an agent thread.
    var selectedRoutine: RoutineSelection?
    /// The question that the routine thread shows first, for example from a notification.
    var focusedQuestion: String?
    /// The refusal of your last answer to each question, by question step.
    var answerErrors: [String: String] = [:]
    /// The floating thread panel.
    var threadsOpen = false
    var threadPage = ThreadPage.conversation
    var drafts: [String: ThreadDraft] = [:]
    /// Each change moves the keyboard focus to the composer.
    var composerFocus = 0
    var selection: SidebarItem? = .runs
    var tab: PluginTab = .ui
    var search = ""
    /// An item that a plugin UI shows once its page is ready, for example from a notification.
    var uiFocus: UIFocus?
    private var started = false

    init(host: PluginHost) {
        self.host = host
        threads = ThreadService(host: host)
        selectedThread = threads.store.threads.first?.id
    }

    func start() {
        guard !started else { return }
        started = true
        host.deliver = { [weak self] item in self?.showNotification(item) }
        host.start()
        Task { await threads.checkAgent() }
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// The thread of a routine, or of the actionables with no owner.
    func routineThread(_ selection: RoutineSelection) -> RoutineThread {
        RoutineThread.build(routine: selection.routine, actionables: host.actionables.all, loaded: Set(host.plugins.map(\.id)))
    }

    /// The open questions of all routines.
    var openQuestions: Int {
        host.plugins.reduce(0) { $0 + routineThread(.routine($1.id)).count }
    }

    /// The selected tab, or the first tab when the plugin does not have it.
    func tab(of plugin: PluginEntry) -> PluginTab {
        let tabs = PluginTab.tabs(of: plugin.manifest)
        return tabs.contains(tab) ? tab : tabs[0]
    }

    func open(pluginId: String) {
        selection = .plugin(pluginId)
        if let plugin = host.plugin(pluginId) { tab = PluginTab.tabs(of: plugin.manifest)[0] }
    }

    /// The plugin UI shows the item after `ready`. A plugin without a UI opens its page only.
    func open(pluginId: String, itemId: String) {
        guard let plugin = host.plugin(pluginId) else { return }
        selection = .plugin(pluginId)
        tab = PluginTab.tabs(of: plugin.manifest)[0]
        guard plugin.manifest.ui != nil, host.item(pluginId: pluginId, itemId: itemId) != nil else { return }
        uiFocus = UIFocus(pluginId: pluginId, itemId: itemId)
    }

    // MARK: Routine threads

    func select(routine: RoutineSelection) {
        withAnimation(.snappy) {
            selectedRoutine = routine
            threadPage = .conversation
        }
    }

    /// Opens the thread panel at a question, for example after a click on its notification.
    func open(question stepId: String, actionableId: String) {
        let owner = host.actionables.actionable(actionableId)?.owner
        selectedRoutine = owner.map { host.plugin($0) == nil ? .noOwner : .routine($0) } ?? .noOwner
        focusedQuestion = stepId
        threadPage = .conversation
        showThreads(true)
    }

    /// Your answer is a trigger with the source `answer`. A refusal shows under its question.
    func answer(_ text: String, question: RoutineThread.Open) {
        answerErrors[question.id] = nil
        host.answer(question: question.id, of: question.actionable.id, text: text) { [weak self] result in
            if case .failure(let error) = result { self?.answerErrors[question.id] = error.description }
        }
    }

    /// Allow once or Always allow a permission question. Always allow saves the allow list first.
    func allow(_ question: RoutineThread.Open, always: Bool) {
        answerErrors[question.id] = nil
        host.answer(question: question.id, of: question.actionable.id, text: nil, grant: always ? .always : .once) { [weak self] result in
            if case .failure(let error) = result { self?.answerErrors[question.id] = error.description }
        }
    }

    func deny(_ question: RoutineThread.Open) {
        if case .failure(let error) = host.deny(question: question.id, of: question.actionable.id) { answerErrors[question.id] = error.description }
    }

    /// Starts a thread, or reuses the selected thread while it has no message.
    func newThread() {
        threadPage = .conversation
        composerFocus += 1
        selectedRoutine = nil
        if let id = selectedThread, threads.store.thread(id)?.items.isEmpty == true { return }
        selectedThread = threads.newThread().id
    }

    func showThreads(_ open: Bool) {
        withAnimation(.spring(duration: 0.45, bounce: 0.18)) { threadsOpen = open }
        guard open else { return }
        if selectedThread == nil { newThread() }
        composerFocus += 1
    }

    func select(thread id: String) {
        selectedThread = id
        selectedRoutine = nil
        withAnimation(.snappy) { threadPage = .conversation }
        composerFocus += 1
    }

    /// Adds the item to the open thread. With the panel closed, the item starts a new thread.
    func askAbout(pluginId: String, cardId: String) {
        guard let item = host.item(pluginId: pluginId, itemId: cardId) else { return }
        if !threadsOpen || threadPage == .list || selectedRoutine != nil { newThread() }
        guard let id = selectedThread else { return }
        let reference = ItemReference(pluginId: pluginId, cardId: cardId, title: item.title)
        if !drafts[id, default: ThreadDraft()].references.contains(reference) { drafts[id, default: ThreadDraft()].references.append(reference) }
        showThreads(true)
    }

    func send(threadId: String) {
        let draft = drafts[threadId, default: ThreadDraft()]
        guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !threads.isRunning(threadId) else { return }
        threads.send(draft.text, references: draft.references, threadId: threadId)
        drafts[threadId] = nil
    }

    func delete(thread id: String) {
        threads.delete(id)
        drafts[id] = nil
        guard selectedThread == id else { return }
        selectedThread = threads.store.threads.first?.id
    }

    var launchAtLogin: Bool {
        get { host.settings.launchAtLogin }
        set {
            host.settings.launchAtLogin = newValue
            guard Bundle.main.bundleIdentifier != nil else { return }
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    private func showNotification(_ item: HostNotification) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.subtitle = host.plugin(item.pluginId).map { [$0.manifest.emoji, $0.manifest.name].compactMap { $0 }.joined(separator: " ") } ?? item.pluginId
        content.userInfo = ["pluginId": item.pluginId, "cardId": item.cardId ?? "", "stepId": item.stepId ?? ""]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let pluginId = info["pluginId"] as? String, let cardId = info["cardId"] as? String else { return }
        let stepId = info["stepId"] as? String ?? ""
        await MainActor.run {
            NSApp.activate()
            if !stepId.isEmpty { return open(question: stepId, actionableId: cardId) }
            if cardId.isEmpty { open(pluginId: pluginId) } else { open(pluginId: pluginId, itemId: cardId) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
