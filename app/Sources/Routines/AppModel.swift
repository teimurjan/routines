import RoutinesKit
import ServiceManagement
import SwiftUI
import UserNotifications

enum SidebarItem: Hashable {
    case inbox
    case threads
    case runs
    case plugin(String)
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

@MainActor
@Observable
final class AppModel: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppModel(host: PluginHost(paths: .standard()))
    let host: PluginHost
    let threads: ThreadService
    var selectedThread: String?
    var selection: SidebarItem? = .inbox
    var tab: PluginTab = .ui
    var search = ""
    /// An item that a plugin UI shows once its page is ready, for example from a notification.
    var uiFocus: BoardItem?
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

    /// The items of all plugins that need you, newest first.
    var needsYou: [BoardItem] {
        host.plugins
            .flatMap { plugin in host.board.cards(of: plugin.id).filter { $0.column == .needsYou }.map { BoardItem(pluginId: plugin.id, card: $0) } }
            .sorted { ($0.card.updatedAt ?? .distantPast) > ($1.card.updatedAt ?? .distantPast) }
    }

    var needsYouCount: Int { needsYou.count }

    func matches(_ card: Card) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        let haystack = [card.title, card.body ?? "", card.status ?? "", (card.tags ?? []).joined(separator: " ")].joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(query)
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
    func open(pluginId: String, cardId: String) {
        guard let plugin = host.plugin(pluginId) else { return }
        selection = .plugin(pluginId)
        tab = PluginTab.tabs(of: plugin.manifest)[0]
        guard plugin.manifest.ui != nil else { return }
        uiFocus = host.board.card(pluginId, cardId).map { BoardItem(pluginId: pluginId, card: $0) }
    }

    /// Starts a thread, or reuses the selected thread while it has no message.
    func newThread() {
        if let id = selectedThread, threads.store.thread(id)?.items.isEmpty == true { return }
        selectedThread = threads.newThread().id
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
        content.userInfo = ["pluginId": item.pluginId, "cardId": item.cardId ?? ""]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let pluginId = info["pluginId"] as? String, let cardId = info["cardId"] as? String else { return }
        await MainActor.run {
            NSApp.activate()
            if cardId.isEmpty { open(pluginId: pluginId) } else { open(pluginId: pluginId, cardId: cardId) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
