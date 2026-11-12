import AppKit
import RoutinesKit

/// The one entry point for a press in the app. Plugin UIs and, until the board goes, the Actions menu come here.
/// An action with `confirm: true` runs only after you press its button in the host dialog. External actions do not come here.
@MainActor
enum ActionGate {
    static let cancelled = HostError.failed("Cancelled.")

    /// Runs an action that the bridge of a plugin UI decided on.
    static func run(_ request: PluginUIAction, pluginId: String, title: String, host: PluginHost) async -> Result<String?, HostError> {
        if request.action.needsConfirmation, await !confirm(request.action, title: title) { return .failure(cancelled) }
        return await withCheckedContinuation { continuation in
            let finished: PluginHost.ActionFinished = { continuation.resume(returning: $0) }
            if let cardId = request.cardId {
                host.perform(request.action.id, cardId: cardId, pluginId: pluginId, text: request.text, finished: finished)
            } else {
                host.performPluginAction(request.action.id, pluginId: pluginId, text: request.text, finished: finished)
            }
        }
    }

    /// A native dialog. Return presses the action button, and Escape presses Cancel.
    private static func confirm(_ action: CardAction, title: String) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(action.label): \(title)"
        let button = alert.addButton(withTitle: action.label)
        button.hasDestructiveAction = action.style == .destructive
        alert.addButton(withTitle: "Cancel")
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return alert.runModal() == .alertFirstButtonReturn }
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }
}
