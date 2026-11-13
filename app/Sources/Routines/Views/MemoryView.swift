import RoutinesKit
import SwiftUI

/// The memory entries, newest first, with a search and filters. You can edit the text and the tags of an entry, and delete it.
struct MemoryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var routine: String?
    @State private var type: MemoryEntry.Kind?

    var body: some View {
        let entries = model.host.memory.entries.filter(matches).sorted { $0.changedAt > $1.changedAt }
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(trail: ["Routines", "Memory"], title: "Memory", subtitle: "What the routines learned from your answers and their steps. Memory never grants a permission.") {
                SearchField(text: $query, prompt: "Search memory")
            }
            HStack(spacing: Tokens.Space.s12) {
                Picker("Routine", selection: $routine) {
                    Text("All routines").tag(String?.none)
                    ForEach(model.host.plugins) { plugin in Text(plugin.manifest.name).tag(Optional(plugin.id)) }
                }
                .frame(maxWidth: 240)
                Picker("Type", selection: $type) {
                    Text("All types").tag(MemoryEntry.Kind?.none)
                    ForEach(MemoryEntry.Kind.allCases, id: \.self) { kind in Text(kind.rawValue.capitalized).tag(Optional(kind)) }
                }
                .frame(maxWidth: 200)
                Spacer()
            }
            .padding(.horizontal, Tokens.Size.pageGutter)
            .padding(.vertical, Tokens.Size.pageTop)
            if entries.isEmpty {
                ContentUnavailableView("No memory yet", systemImage: "brain", description: Text("Entries show here after the routines take steps."))
            } else {
                List(entries) { entry in MemoryRow(entry: entry) }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, Tokens.Space.s16)
            }
        }
    }

    private func matches(_ entry: MemoryEntry) -> Bool {
        if let routine, entry.routine != routine { return false }
        if let type, entry.type != type { return false }
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || ([entry.text] + entry.tags).contains { $0.localizedCaseInsensitiveContains(text) }
    }
}

private struct MemoryRow: View {
    @Environment(AppModel.self) private var model
    var entry: MemoryEntry
    @State private var editing = false
    @State private var text = ""
    @State private var tags = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            HStack(spacing: Tokens.Space.s6) {
                Text(entry.type.rawValue.capitalized).font(Tokens.Font.label).padding(Tokens.Padding.pill).background(Theme.pill, in: Capsule())
                Text(model.host.plugin(entry.routine)?.manifest.name ?? entry.routine).font(Tokens.Font.meta).foregroundStyle(Theme.muted)
                Button(model.host.actionables.actionable(entry.actionable)?.title ?? "Actionable \(entry.actionable)") {
                    model.open(pluginId: entry.routine, itemId: entry.actionable)
                }
                .buttonStyle(.link)
                .font(Tokens.Font.meta)
                .help("Step \(entry.step)")
                Spacer()
                Text(entry.changedAt.shortDay).font(Tokens.Font.meta).foregroundStyle(Theme.faint)
            }
            if editing {
                TextField("Text", text: $text, axis: .vertical).lineLimit(1...8)
                TextField("Tags, separated by commas", text: $tags)
                HStack {
                    Button("Save", action: save).controlSize(.small)
                    Button("Cancel") { editing = false }.controlSize(.small)
                }
                if let error { Text(error).font(Tokens.Font.small).foregroundStyle(Theme.danger) }
            } else {
                Text(entry.text).font(Tokens.Font.body).textSelection(.enabled)
                if !entry.tags.isEmpty { Text(entry.tags.joined(separator: " · ")).font(Tokens.Font.meta).foregroundStyle(Theme.muted) }
            }
        }
        .padding(.vertical, Tokens.Space.s4)
        .contextMenu {
            Button("Edit", systemImage: "pencil") {
                text = entry.text
                tags = entry.tags.joined(separator: ", ")
                error = nil
                editing = true
            }
            Button("Delete", systemImage: "trash", role: .destructive) { model.host.memory.delete(id: entry.id) }
        }
    }

    private func save() {
        let list = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        switch model.host.memory.edit(id: entry.id, text: text, tags: list) {
        case .success: editing = false
        case .failure(let failure): error = failure.description
        }
    }
}
