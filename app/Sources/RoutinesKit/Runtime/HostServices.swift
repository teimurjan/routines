import Foundation

/// The shared parts of the host that a bridge reaches. The stores live on the main actor, because the views observe them.
public final class HostServices: Sendable {
    let locks: LockService
    let browser: BrowserService
    private let boardStore: BoardStore
    private let notesStore: NotesStore
    private let notificationStore: NotificationStore
    private let pageStore: PageStore
    private let activity: @MainActor @Sendable (String, Date) -> Activity
    private let deliver: @MainActor @Sendable (HostNotification) -> Void
    private let runLater: @MainActor @Sendable (String, Int) -> Void

    @MainActor
    init(
        locks: LockService, browser: BrowserService, board: BoardStore, notes: NotesStore, notifications: NotificationStore,
        pages: PageStore, activity: @escaping @MainActor @Sendable (String, Date) -> Activity,
        deliver: @escaping @MainActor @Sendable (HostNotification) -> Void, runLater: @escaping @MainActor @Sendable (String, Int) -> Void = { _, _ in }
    ) {
        self.locks = locks
        self.browser = browser
        boardStore = board
        notesStore = notes
        notificationStore = notifications
        pageStore = pages
        self.activity = activity
        self.deliver = deliver
        self.runLater = runLater
    }

    func requestRun(pluginId: String, delayMs: Int) async {
        await MainActor.run { runLater(pluginId, delayMs) }
    }

    func board<T: Sendable>(_ work: @MainActor @Sendable (BoardStore) -> T) async -> T {
        await MainActor.run { work(boardStore) }
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
