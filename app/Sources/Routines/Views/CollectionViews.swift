import RoutinesKit
import SwiftUI

/// The items of all routines that need you, newest first. A row opens the plugin, and its UI shows the item.
struct InboxView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(trail: ["Routines", "Inbox"], title: "Inbox", subtitle: "The items of all routines that need you, newest first.") {
                SearchField(text: $model.search)
            }
            .padding(.bottom, Tokens.Size.pageTop)
            let items = model.needsYou.filter { model.matches($0.card) }
            if items.isEmpty {
                ContentUnavailableView("Nothing needs you", systemImage: "tray", description: Text("New items show here when a routine asks you."))
            } else {
                List(items) { item in InboxRow(item: item) }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, Tokens.Space.s16)
            }
        }
    }
}

/// The plugin mark, the title, one line of the body, the status and the date of an item.
private struct InboxRow: View {
    @Environment(AppModel.self) private var model
    var item: BoardItem

    var body: some View {
        let card = item.card
        HStack(spacing: Tokens.Space.s12) {
            if let plugin = model.host.plugin(item.pluginId) {
                PluginMark(plugin: plugin).frame(width: 18).help(plugin.manifest.name)
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text(card.title).font(Tokens.Font.rowTitle).lineLimit(1)
                if let body = card.body, !body.isEmpty {
                    Text(Markdown.attributed(body)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                if let status = card.status, !status.isEmpty {
                    Text(status).foregroundStyle(status.hasPrefix("Error") ? Theme.danger : Theme.muted).lineLimit(1)
                }
            }
            Spacer()
            Text((card.dateValue ?? card.updatedAt ?? Date()).shortDay).foregroundStyle(Theme.muted).frame(width: 60, alignment: .trailing)
        }
        .font(Tokens.Font.meta)
        .padding(.vertical, Tokens.Space.s4)
        .contentShape(Rectangle())
        .onTapGesture { model.open(pluginId: item.pluginId, cardId: card.id) }
    }
}

enum Markdown {
    static func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
