import RoutinesKit
import SwiftUI

/// The page of a plugin: its UI, then Runs and Settings. The UI draws the items and the actions of the plugin.
struct PluginView: View {
    @Environment(AppModel.self) private var model
    var plugin: PluginEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(trail: ["Routines", plugin.manifest.name], title: [plugin.manifest.emoji, plugin.manifest.name].compactMap { $0 }.joined(separator: " "), subtitle: plugin.manifest.description) {
                EmptyView()
            }
            if let blocker = model.host.blocker(plugin.id) {
                Banner(text: blocker).padding(.horizontal, Tokens.Size.pageGutter).padding(.top, Tokens.Space.s12)
            }
            if plugin.manifest.ui == nil {
                Banner(text: "This plugin has no UI. The Inbox lists its items that need you.").padding(.horizontal, Tokens.Size.pageGutter).padding(.top, Tokens.Space.s12)
            }
            let tab = model.tab(of: plugin)
            TabStrip(tabs: PluginTab.tabs(of: plugin.manifest), label: { $0.label(in: plugin.manifest) }, selection: Binding(get: { tab }, set: { model.tab = $0 }))
                .padding(.horizontal, Tokens.Size.pageGutter)
                .padding(.vertical, Tokens.Size.pageTop)
            switch tab {
            // A new identity per plugin and per build, so the web view of the last plugin or the last build does not stay on screen.
            case .ui: PluginUIView(plugin: plugin).id(plugin.id + plugin.stamp)
            case .runs: RunsView(pluginId: plugin.id)
            case .settings: PluginSettingsView(plugin: plugin)
            }
        }
    }
}

struct Banner: View {
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text(text).font(Tokens.Font.small).textSelection(.enabled)
            Spacer()
        }
        .padding(10)
        .background(Theme.warning.opacity(Tokens.Opacity.tint), in: RoundedRectangle(cornerRadius: Tokens.Radius.track))
    }
}
