import RoutinesKit
import SwiftUI

/// The field of a thread, with the items that you added, the agent and the send or stop button.
struct ThreadComposer: View {
    @Environment(AppModel.self) private var model
    var thread: AgentThread
    var running: Bool
    @FocusState private var focused: Bool
    @State private var showSettings = false

    var body: some View {
        let draft = Binding(get: { model.drafts[thread.id, default: ThreadDraft()] }, set: { model.drafts[thread.id] = $0 })
        let canSend = !running && !draft.wrappedValue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.bubble, style: .continuous)
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            if !draft.wrappedValue.references.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: Tokens.Space.s4) {
                        ForEach(draft.wrappedValue.references, id: \.self) { reference in
                            ReferenceChip(reference: reference) {
                                withAnimation(.snappy) { draft.wrappedValue.references.removeAll { $0 == reference } }
                            }
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            TextField(placeholder(draft.wrappedValue.references), text: draft.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Tokens.Font.bodyLarge)
                .lineLimit(1...10)
                .focused($focused)
                .onSubmit { model.send(threadId: thread.id) }
            HStack(spacing: Tokens.Space.s8) {
                AgentChip(provider: thread.provider) { showSettings = true }
                Spacer(minLength: 0)
                Text(running ? "⌘. to stop" : "↩ to send · ⌥↩ for a new line")
                    .font(Tokens.Font.caption)
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
                SendButton(running: running, enabled: canSend, send: { model.send(threadId: thread.id) }, stop: { model.threads.stop(thread.id) })
            }
        }
        .padding(Tokens.Space.s12)
        .background(shape.fill(Theme.canvas.opacity(0.55)))
        .overlay(shape.strokeBorder(focused ? Color.accentColor.opacity(0.5) : Theme.cardBorder))
        .animation(.snappy, value: focused)
        .animation(.snappy, value: draft.wrappedValue.references)
        .padding([.horizontal, .bottom], Tokens.Space.s12)
        .onChange(of: model.composerFocus, initial: true) { focused = true }
        .sheet(isPresented: $showSettings) { AgentSettingsView() }
    }

    private func placeholder(_ references: [ItemReference]) -> String {
        if let only = references.first, references.count == 1 { return "Ask about “\(only.title)”…" }
        if !references.isEmpty { return "Ask about these \(references.count) items…" }
        return thread.items.isEmpty ? "Describe a routine, or ask anything…" : "Reply to the agent…"
    }
}

/// The agent of the thread with the state of its login. A click opens the agent settings.
private struct AgentChip: View {
    @Environment(AppModel.self) private var model
    var provider: AgentProvider
    var action: () -> Void

    var body: some View {
        let status = provider == model.threads.config.provider ? model.threads.status : nil
        Button(action: action) {
            HStack(spacing: Tokens.Space.s6) {
                Circle()
                    .fill(status == nil ? Theme.faint : status?.ready == true ? Theme.success : Theme.danger)
                    .frame(width: Tokens.Space.s6, height: Tokens.Space.s6)
                Text(provider.name)
                Image(systemName: "chevron.up.chevron.down").font(Tokens.Font.micro).foregroundStyle(Theme.faint)
            }
            .font(Tokens.Font.button)
            .foregroundStyle(Theme.muted)
            .padding(Tokens.Padding.pill)
            .background(Capsule().fill(.quaternary))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(status?.detail ?? "The coding agent of this thread. A new thread uses the agent of the settings.")
    }
}

private struct SendButton: View {
    var running: Bool
    var enabled: Bool
    var send: () -> Void
    var stop: () -> Void

    var body: some View {
        Group {
            if running {
                Button(action: stop) { icon("stop.fill", fill: Theme.text) }
                    .keyboardShortcut(".", modifiers: .command)
                    .help("Stop the turn (⌘.)")
            } else {
                Button(action: send) { icon("arrow.up", fill: enabled ? Color.accentColor : Theme.faint.opacity(0.4)) }
                    .disabled(!enabled)
                    .help("Send (↩)")
            }
        }
        .buttonStyle(.plain)
        .contentTransition(.symbolEffect(.replace))
        .animation(.snappy, value: running)
        .animation(.snappy, value: enabled)
    }

    private func icon(_ name: String, fill: Color) -> some View {
        Image(systemName: name)
            .font(Tokens.Font.body.weight(.bold))
            .foregroundStyle(running ? Theme.canvas : Theme.onAccent)
            .frame(width: Tokens.Space.s28, height: Tokens.Space.s28)
            .background(Circle().fill(fill))
            .contentShape(Circle())
    }
}
