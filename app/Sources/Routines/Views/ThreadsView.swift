import RoutinesKit
import SwiftUI

/// Conversations with the coding agent, which makes and changes routines in the workspace. A list of threads at the left and the open thread at the right.
struct ThreadsView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(trail: ["Routines", "Threads"], title: "Threads", subtitle: "Ask the coding agent to make a routine, change one or explain a failed run.") {
                AgentButton { showSettings = true }
            }
            ForEach(problems, id: \.self) { problem in
                Banner(text: problem).padding(.horizontal, Tokens.Size.pageGutter).padding(.top, Tokens.Space.s12)
            }
            HStack(spacing: 0) {
                ThreadList().frame(width: 250)
                Divider()
                if let id = model.selectedThread, let thread = model.threads.store.thread(id) {
                    ThreadDetail(thread: thread).id(thread.id)
                } else {
                    ContentUnavailableView("No thread", systemImage: "bubble.left.and.text.bubble.right", description: Text("Press New thread to start one."))
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.cardBorder))
            .padding(.horizontal, Tokens.Size.pageGutter)
            .padding(.vertical, Tokens.Size.pageTop)
        }
        .sheet(isPresented: $showSettings) { AgentSettingsView() }
    }

    private var problems: [String] {
        let status = model.threads.status
        let notReady = status.flatMap { $0.ready ? nil : $0.detail }
        return [model.host.workspaceProblem, notReady, status?.warning].compactMap { $0 }
    }
}

/// The agent of new threads and its state. A click opens the agent settings.
private struct AgentButton: View {
    @Environment(AppModel.self) private var model
    var action: () -> Void

    var body: some View {
        let status = model.threads.status
        Button(action: action) {
            HStack(spacing: Tokens.Space.s6) {
                Circle().fill(status == nil ? Theme.faint : status?.ready == true ? Theme.success : Theme.danger).frame(width: Tokens.Space.s8, height: Tokens.Space.s8)
                Text(model.threads.config.provider.name)
                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.muted)
            }
            .font(Tokens.Font.button)
            .padding(Tokens.Padding.button)
            .background(Theme.pill, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
        }
        .buttonStyle(.plain)
        .help(status?.detail ?? "Checking the agent…")
    }
}

private struct ThreadList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            Button { model.newThread() } label: {
                Label("New thread", systemImage: "square.and.pencil").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .font(Tokens.Font.rowTitle)
            .padding(Tokens.Padding.field)
            .keyboardShortcut("n", modifiers: [.command])
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    ForEach(model.threads.store.threads) { thread in ThreadRow(thread: thread) }
                }
            }
        }
        .padding(Tokens.Space.s8)
    }
}

private struct ThreadRow: View {
    @Environment(AppModel.self) private var model
    var thread: AgentThread

    var body: some View {
        let selected = model.selectedThread == thread.id
        Button { model.selectedThread = thread.id } label: {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                HStack {
                    Text(thread.title).font(Tokens.Font.rowTitle).lineLimit(1)
                    Spacer(minLength: 0)
                    if model.threads.isRunning(thread.id) { ProgressView().controlSize(.mini) }
                }
                Text("\(thread.provider.name) · \(thread.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(Tokens.Font.meta).foregroundStyle(Theme.faint)
            }
            .padding(Tokens.Padding.field)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: Tokens.Radius.field))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) {
                model.threads.delete(thread.id)
                if model.selectedThread == thread.id { model.selectedThread = model.threads.store.threads.first?.id }
            }
        }
    }
}

private struct ThreadDetail: View {
    @Environment(AppModel.self) private var model
    var thread: AgentThread
    @State private var draft = ""
    private let bottom = "bottom"

    var body: some View {
        let running = model.threads.isRunning(thread.id)
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Tokens.Space.s12) {
                        if thread.items.isEmpty { EmptyThread() }
                        ForEach(thread.items) { item in ItemView(item: item, workspace: model.host.paths.workspaceDir) }
                        if running {
                            HStack(spacing: Tokens.Space.s6) {
                                ProgressView().controlSize(.small)
                                Text("Working…").font(Tokens.Font.small).foregroundStyle(Theme.muted)
                            }
                        } else {
                            TouchedRoutines(ids: thread.touchedPlugins)
                        }
                        Color.clear.frame(height: Tokens.Space.s1).id(bottom)
                    }
                    .padding(Tokens.Space.s20)
                    .textSelection(.enabled)
                }
                .onAppear { proxy.scrollTo(bottom, anchor: .bottom) }
                .onChange(of: thread.items) { proxy.scrollTo(bottom, anchor: .bottom) }
            }
            Divider()
            Composer(draft: $draft, running: running, send: send, stop: { model.threads.stop(thread.id) })
        }
    }

    private func send() {
        model.threads.send(draft, threadId: thread.id)
        draft = ""
    }
}

private struct EmptyThread: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            Text("What should the agent do?").font(Tokens.Font.subhead)
            Text("For example: make a routine that checks my site every hour and tells me when it is down. Or: change a routine, so it runs only on weekdays.")
                .font(Tokens.Font.body).foregroundStyle(Theme.muted)
        }
    }
}

private struct Composer: View {
    @Binding var draft: String
    var running: Bool
    var send: () -> Void
    var stop: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Tokens.Space.s8) {
            TextField("Message the agent", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Tokens.Font.bodyLarge)
                .lineLimit(1...8)
                .onSubmit { if !running { send() } }
            if running {
                Button(action: stop) { Image(systemName: "stop.circle.fill") }
                    .help("Stop the turn")
            } else {
                Button(action: send) { Image(systemName: "arrow.up.circle.fill") }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send")
            }
        }
        .buttonStyle(.plain)
        .font(Tokens.Font.title)
        .foregroundStyle(Theme.muted)
        .padding(Tokens.Space.s14)
    }
}

private struct ItemView: View {
    var item: ThreadItem
    var workspace: String

    var body: some View {
        switch item.kind {
        case .user:
            HStack {
                Spacer(minLength: Tokens.Space.s28)
                Text(item.text).font(Tokens.Font.bodyLarge)
                    .padding(Tokens.Padding.field)
                    .background(Theme.pill, in: RoundedRectangle(cornerRadius: Tokens.Radius.field))
            }
        case .message:
            Text(markdown(item.text)).font(Tokens.Font.bodyLarge).frame(maxWidth: .infinity, alignment: .leading)
        case .reasoning:
            Text(item.text).font(Tokens.Font.small).italic().foregroundStyle(Theme.muted)
        case .error:
            HStack(alignment: .top, spacing: Tokens.Space.s8) {
                Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(Theme.danger)
                Text(item.text).font(Tokens.Font.small)
            }
        case .command, .fileChange, .tool:
            ToolRow(item: item, title: relative(item.title))
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    /// Paths in the workspace show from the workspace folder.
    private func relative(_ title: String) -> String {
        title.replacingOccurrences(of: workspace + "/", with: "")
    }
}

/// A command, a file change or another tool call. Its output opens on a click.
private struct ToolRow: View {
    var item: ThreadItem
    var title: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            Button { open.toggle() } label: {
                HStack(spacing: Tokens.Space.s6) {
                    Image(systemName: icon).frame(width: Tokens.Space.s16).foregroundStyle(Theme.muted)
                    Text(title).font(Tokens.Font.mono.monospaced()).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    state
                    if !item.text.isEmpty { Image(systemName: open ? "chevron.down" : "chevron.right").font(Tokens.Font.micro).foregroundStyle(Theme.faint) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open, !item.text.isEmpty {
                Text(item.text)
                    .font(Tokens.Font.mono.monospaced())
                    .foregroundStyle(Theme.muted)
                    .padding(Tokens.Padding.field)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.column, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
            }
        }
    }

    private var icon: String {
        switch item.kind {
        case .command: "terminal"
        case .fileChange: "pencil"
        default: "wrench.and.screwdriver"
        }
    }

    @ViewBuilder private var state: some View {
        switch item.state {
        case .running: ProgressView().controlSize(.mini)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.danger)
        case .done: EmptyView()
        }
    }
}

/// The routines that the thread changed, each with a button that opens it.
private struct TouchedRoutines: View {
    @Environment(AppModel.self) private var model
    var ids: [String]

    var body: some View {
        let plugins = ids.compactMap { model.host.plugin($0) }
        if !plugins.isEmpty {
            HStack(spacing: Tokens.Space.s8) {
                ForEach(plugins) { plugin in
                    Button { model.open(pluginId: plugin.id) } label: {
                        HStack(spacing: Tokens.Space.s6) {
                            PluginMark(plugin: plugin, size: 13)
                            Text("Open \(plugin.manifest.name)")
                            if plugin.problem != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
                        }
                        .font(Tokens.Font.button)
                        .padding(Tokens.Padding.button)
                        .background(Theme.pill, in: RoundedRectangle(cornerRadius: Tokens.Radius.control))
                    }
                    .buttonStyle(.plain)
                    .help(plugin.problem ?? plugin.manifest.description)
                }
            }
        }
    }
}
