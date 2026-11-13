import RoutinesKit
import SwiftUI

/// The left panel of the design: the brand, the views, the search and one row per routine with its color dot. Pinned routines come first.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        let shown = model.host.plugins.filter { !$0.manifest.hidden && matches($0) }
        let settings = model.host.settings
        let pinned = settings.pinned.compactMap { id in shown.first { $0.id == id } }
        let others = shown.filter { !settings.isPinned($0.id) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                brand.padding(.bottom, 14)
                row(.runs, title: "Runs", icon: "clock.arrow.circlepath", badge: model.host.running.count)
                row(.memory, title: "Memory", icon: "brain", badge: 0)
                SearchField(text: $query, prompt: "Search routines", width: nil).padding(.top, 22)
                if !pinned.isEmpty {
                    section("PINNED")
                    ForEach(pinned) { plugin in PluginRow(plugin: plugin) }
                }
                if !others.isEmpty {
                    section("ROUTINES")
                    ForEach(others) { plugin in PluginRow(plugin: plugin) }
                }
                if shown.isEmpty {
                    Text("No routines match.").font(Tokens.Font.small).foregroundStyle(Theme.faint).padding(.horizontal, 10).padding(.top, 14)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.never)
        .background(Theme.sidebar)
    }

    private func matches(_ plugin: PluginEntry) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }
        return [plugin.id, plugin.manifest.name, plugin.manifest.description].contains { $0.localizedCaseInsensitiveContains(text) }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(Tokens.Font.caption)
            .tracking(0.6)
            .foregroundStyle(Theme.faint)
            .padding(.horizontal, 10)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    private var brand: some View {
        HStack {
            if let wordmark = Bundle.module.image(forResource: "wordmark") {
                Image(nsImage: wordmark)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 24)
                    .accessibilityLabel("Routines")
            }
            Spacer()
        }
        .padding(.horizontal, 10)
    }

    private func row(_ item: SidebarItem, title: String, icon: String, badge: Int) -> some View {
        SidebarButton(item: item) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(Theme.muted)
            Text(title)
            if badge > 0 {
                Text("\(badge)")
                    .font(Tokens.Font.label)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Theme.pill, in: Capsule())
            }
            Spacer()
        }
    }
}

private struct SidebarButton<Label: View>: View {
    @Environment(AppModel.self) private var model
    var item: SidebarItem
    @ViewBuilder var label: Label

    var body: some View {
        let selected = model.selection == item
        Button { model.selection = item } label: {
            HStack(spacing: 10) { label }
                .font(Tokens.Font.bodyLarge.weight(selected ? .medium : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(selected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: Tokens.Radius.field))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PluginRow: View {
    @Environment(AppModel.self) private var model
    var plugin: PluginEntry

    var body: some View {
        let waiting = model.routineThread(.routine(plugin.id)).count
        let pinned = model.host.settings.isPinned(plugin.id)
        SidebarButton(item: .plugin(plugin.id)) {
            PluginMark(plugin: plugin, size: 15).frame(width: 20)
            Text(plugin.manifest.name).lineLimit(1)
            Spacer()
            if model.host.running.contains(plugin.id) {
                ProgressView().controlSize(.mini)
            } else if plugin.problem != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning).help(plugin.problem ?? "")
            } else if !model.host.settings.isEnabled(plugin.id) {
                Image(systemName: "pause.circle").foregroundStyle(Theme.faint)
            }
            if waiting > 0 {
                Text("\(waiting)").font(Tokens.Font.label).foregroundStyle(Theme.muted)
            }
        }
        .contextMenu {
            Button(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin") {
                model.host.settings.setPinned(!pinned, pluginId: plugin.id)
            }
        }
    }
}
