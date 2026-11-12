import RoutinesKit
import SwiftUI

struct PluginSettingsView: View {
    @Environment(AppModel.self) private var model
    var plugin: PluginEntry
    @State private var draftNote = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Run this routine", isOn: Binding(
                    get: { model.host.settings.isEnabled(plugin.id) },
                    set: { model.host.settings.setEnabled($0, pluginId: plugin.id) }))
                LabeledContent("Schedule", value: ScheduleText.describe(plugin.manifest.schedule, atLaunch: plugin.manifest.runAtLaunch))
                Picker("Delete done and failed cards", selection: Binding(
                    get: { model.host.retentionDays(plugin.id) },
                    set: { model.host.setRetentionDays($0, pluginId: plugin.id) })
                ) {
                    ForEach(Retention.choices(including: model.host.retentionDays(plugin.id)), id: \.self) { days in
                        Text(Retention.label(days)).tag(days)
                    }
                }
                LabeledContent("Folder", value: plugin.dir).textSelection(.enabled)
                if let problem = plugin.problem { LabeledContent("Problem") { Text(problem).foregroundStyle(Theme.danger) } }
            }
            if !plugin.manifest.settings.isEmpty {
                Section("Settings") {
                    ForEach(plugin.manifest.settings) { field in
                        TextField(
                            text: Binding(
                                get: { model.host.settings.value(field, pluginId: plugin.id) },
                                set: { model.host.settings.set($0, field: field, pluginId: plugin.id) }),
                            prompt: Text(field.defaultValue ?? field.placeholder ?? "")
                        ) {
                            HStack(spacing: 4) {
                                Text(field.label)
                                if field.required { Text("required").font(.caption).foregroundStyle(Theme.faint) }
                                if field.shared { Image(systemName: "link").font(.caption).foregroundStyle(Theme.faint).help("Shared with other routines") }
                            }
                        }
                    }
                }
            }
            Section {
                ForEach(model.host.notes.notes(of: plugin.id)) { note in
                    HStack(alignment: .top) {
                        Text("#\(note.number)").foregroundStyle(Theme.faint).monospacedDigit()
                        Text(note.text).textSelection(.enabled)
                        Spacer()
                        Button { model.host.notes.remove(note.number, pluginId: plugin.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Add a note for this routine", text: $draftNote).onSubmit(addNote)
                    Button("Add", action: addNote).disabled(draftNote.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Notes")
            } footer: {
                Text("The agents of this routine read your notes. Only you can add one.").foregroundStyle(Theme.faint)
            }
            Section("Permissions") {
                LabeledContent("Commands", value: list(plugin.manifest.permissions.exec))
                LabeledContent("Hosts", value: list(plugin.manifest.permissions.hosts))
                LabeledContent("Paths", value: list(plugin.manifest.permissions.paths))
                LabeledContent("Browser", value: plugin.manifest.permissions.browser ? "Yes" : "No")
                LabeledContent("Activity", value: plugin.manifest.permissions.activity ? "Reads all routines" : "No")
            }
            Section("App") {
                Toggle("Open Routines at login", isOn: $model.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 12)
    }

    private func addNote() {
        model.host.notes.add(draftNote, pluginId: plugin.id)
        draftNote = ""
    }

    private func list(_ values: [String]) -> String {
        values.isEmpty ? "None" : values.joined(separator: ", ")
    }
}

enum ScheduleText {
    static func describe(_ slots: [ClockSlot], atLaunch: Bool) -> String {
        let parts = slots.map(describe)
        let text = parts.isEmpty ? "Only on demand" : parts.joined(separator: ", ")
        return atLaunch ? "\(text), and at launch" : text
    }

    private static func describe(_ slot: ClockSlot) -> String {
        let minute = slot.minute.map { String(format: "%02d", $0) }
        switch (slot.hour, minute) {
        case (nil, nil): return "every minute"
        case (nil, let minute?): return "at :\(minute)"
        case (let hour?, let minute): return "at \(hour):\(minute ?? "**")"
        }
    }
}

enum Retention {
    static let standard = [1, 7, 14, 30, 0]

    // A value from a manifest that is not standard stays in the list, so the picker can show it.
    static func choices(including current: Int) -> [Int] {
        standard.contains(current) ? standard : (standard.dropLast() + [current]).sorted() + [0]
    }

    static func label(_ days: Int) -> String {
        switch days {
        case 0: "Never"
        case 1: "After 1 day"
        default: "After \(days) days"
        }
    }
}
