import RoutinesKit
import SwiftUI

struct RoutinesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Routines", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1000, minHeight: 640)
                .task { model.start() }
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .windowToolbarFullScreenVisibility(.onHover)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Reload Plugins") { model.host.reload() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarMenu().environment(model)
        } label: {
            Image(systemName: model.needsYouCount > 0 ? "square.grid.2x2.fill" : "square.grid.2x2")
        }
    }
}

private struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.needsYouCount == 1 ? "1 card needs you" : "\(model.needsYouCount) cards need you")
        Button("Open Routines") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Divider()
        Button("Quit Routines") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Receives `routines://` URLs even when no window is open.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            AppModel.shared.start()
            for request in urls.compactMap(ExternalAction.parse) { AppModel.shared.host.performExternal(request) }
        }
    }
}
