import Foundation

/// The shared parts of the host that a bridge reaches. The stores live on the main actor, because the views observe them.
public final class HostServices: Sendable {
    let locks: LockService
    let browser: BrowserService
    private let notesStore: NotesStore
    private let notificationStore: NotificationStore
    private let pageStore: PageStore
    private let activity: @MainActor @Sendable (String, Date) -> Activity
    private let actionables: @MainActor @Sendable (String, String, ActionableCall) -> Result<String, HostError>
    private let deliver: @MainActor @Sendable (HostNotification) -> Void
    private let runLater: @MainActor @Sendable (String, Int) -> Void

    @MainActor
    init(
        locks: LockService, browser: BrowserService, notes: NotesStore, notifications: NotificationStore,
        pages: PageStore, activity: @escaping @MainActor @Sendable (String, Date) -> Activity,
        actionables: @escaping @MainActor @Sendable (String, String, ActionableCall) -> Result<String, HostError> = { _, _, _ in .failure(.failed("no actionables")) },
        deliver: @escaping @MainActor @Sendable (HostNotification) -> Void, runLater: @escaping @MainActor @Sendable (String, Int) -> Void = { _, _ in }
    ) {
        self.locks = locks
        self.browser = browser
        notesStore = notes
        notificationStore = notifications
        pageStore = pages
        self.activity = activity
        self.actionables = actionables
        self.deliver = deliver
        self.runLater = runLater
    }

    func requestRun(pluginId: String, delayMs: Int) async {
        await MainActor.run { runLater(pluginId, delayMs) }
    }

    /// `trigger` is the id of the decision that started the call, so each step names it.
    func actionables(pluginId: String, trigger: String, _ call: ActionableCall) async -> Result<String, HostError> {
        await MainActor.run { actionables(pluginId, trigger, call) }
    }

    func notes<T: Sendable>(_ work: @MainActor @Sendable (NotesStore) -> T) async -> T {
        await MainActor.run { work(notesStore) }
    }

    func activity(reader: String, since: Date) async -> Activity {
        await MainActor.run { activity(reader, since) }
    }

    func pages<T: Sendable>(_ work: @MainActor @Sendable (PageStore) -> T) async -> T {
        await MainActor.run { work(pageStore) }
    }

    func notify(pluginId: String, title: String, body: String, cardId: String?) async {
        await MainActor.run {
            let item = notificationStore.add(pluginId: pluginId, title: title, body: body, cardId: cardId)
            deliver(item)
        }
    }
}
