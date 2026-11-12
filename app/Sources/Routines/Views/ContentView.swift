import RoutinesKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            Group {
                switch model.selection {
                case .inbox, nil: InboxView()
                case .threads: ThreadsView()
                case .runs: RunsView(pluginId: nil)
                case .plugin(let id):
                    if let plugin = model.host.plugin(id) { PluginView(plugin: plugin) } else { ContentUnavailableView("No plugin", systemImage: "puzzlepiece") }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.canvas)
        }
    }
}

/// The breadcrumb, the title and the line under it, as at the top of the design.
struct PageHeader<Trailing: View>: View {
    var trail: [String]
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(Array(trail.enumerated()), id: \.offset) { index, part in
                        if index > 0 { Image(systemName: "chevron.right").font(Tokens.Font.micro).foregroundStyle(Theme.faint) }
                        Text(part).foregroundStyle(index == trail.count - 1 ? .primary : Theme.muted)
                    }
                }
                .font(Tokens.Font.body)
                Text(title).font(Tokens.Font.display)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(Tokens.Font.body).foregroundStyle(Theme.muted).lineLimit(2)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, Tokens.Size.pageGutter)
        .padding(.top, Tokens.Size.pageTop)
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt = "Search anything…"
    /// A nil width fills the space that the parent offers.
    var width: CGFloat? = 240

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.faint)
            TextField(prompt, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faint) }.buttonStyle(.plain)
            }
        }
        .font(Tokens.Font.body)
        .padding(Tokens.Padding.field)
        .frame(width: width)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: Tokens.Radius.field))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.field).strokeBorder(Theme.cardBorder))
    }
}

/// The segmented control of the design: a gray track with a white selected segment.
struct TabStrip<Tab: Hashable & Identifiable>: View {
    var tabs: [Tab]
    var label: (Tab) -> String
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button { selection = tab } label: {
                    Text(label(tab))
                        .font(Tokens.Font.body.weight(selection == tab ? .semibold : .regular))
                        .foregroundStyle(selection == tab ? .primary : Theme.muted)
                        .frame(minWidth: Tokens.Size.tabMinWidth)
                        .padding(Tokens.Padding.tab)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(Theme.card).shadow(Tokens.Shadow.segment)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Tokens.Space.s3)
        .background(Theme.pill, in: RoundedRectangle(cornerRadius: Tokens.Radius.track))
    }
}
