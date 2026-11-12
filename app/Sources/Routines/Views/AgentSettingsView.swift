import RoutinesKit
import SwiftUI

/// The coding agent of the threads: the CLI, the model and the effort, with the state of its login.
struct AgentSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false

    var body: some View {
        let threads = model.threads
        let config = Binding(get: { threads.config }, set: { threads.config = $0 })
        VStack(alignment: .leading, spacing: 0) {
            Text("Coding agent").font(Tokens.Font.title).padding([.horizontal, .top], Tokens.Space.s20)
            Form {
                Section {
                    Picker("Agent", selection: config.provider) {
                        ForEach(AgentProvider.allCases) { provider in Text(provider.name).tag(provider) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Model", text: Binding(get: { config.wrappedValue.model ?? "" }, set: { config.wrappedValue.model = $0 }), prompt: Text("Default"))
                    Picker("Effort", selection: config.effort) {
                        Text("Default").tag(AgentEffort?.none)
                        ForEach(AgentEffort.allCases) { effort in Text(effort.rawValue).tag(AgentEffort?.some(effort)) }
                    }
                } footer: {
                    Text("A new thread uses this agent. A thread keeps the agent that it started with.").foregroundStyle(Theme.faint)
                }
                Section("State") {
                    HStack {
                        if checking { ProgressView().controlSize(.small) }
                        Text(threads.status?.detail ?? "Not checked yet.").textSelection(.enabled)
                        Spacer()
                        Button("Check again") { check() }.disabled(checking)
                    }
                    if let warning = threads.status?.warning { Text(warning).foregroundStyle(Theme.warning) }
                    LabeledContent("Workspace", value: model.host.paths.workspaceDir)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(Tokens.Space.s20)
        }
        .frame(width: 520)
        .background(Theme.canvas)
    }

    private func check() {
        checking = true
        Task {
            await model.threads.checkAgent()
            checking = false
        }
    }
}
