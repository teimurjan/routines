import AppKit
import RoutinesKit

/// The one entry point for a press in the app. Each press becomes a trigger with the source `ui`.
/// An action or a transition with `confirm: true` runs only after you press its button in the host dialog.
@MainActor
enum ActionGate {
    static let cancelled = HostError.failed("Cancelled.")

    /// Runs an action or a transition that the bridge of a plugin UI decided on.
    static func run(_ request: PluginUIAction, pluginId: String, title: String, host: PluginHost) async -> Result<String?, HostError> {
        if request.action.needsConfirmation, await !confirm(request.action, title: title) { return .failure(cancelled) }
        let trigger = trigger(for: request, pluginId: pluginId, host: host)
        return await withCheckedContinuation { continuation in
            host.submit(trigger) { continuation.resume(returning: $0) }
        }
    }

    /// A transition names its actionable. An item action of a plugin of today names its card, which the store finds by its key.
    private static func trigger(for request: PluginUIAction, pluginId: String, host: PluginHost) -> Trigger {
        let at = Date()
        if let id = request.actionableId ?? request.cardId.flatMap({ host.item(pluginId: pluginId, itemId: $0)?.id }) {
            return .transition(request.action.id, of: id, routine: pluginId, source: .ui, text: request.text, at: at)
        }
        return Trigger(routine: pluginId, source: .ui, work: .action, transition: request.action.id, text: request.text, at: at)
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
