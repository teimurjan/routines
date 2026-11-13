import RoutinesKit
import SwiftUI

/// The glass panel of the threads: a header, then the open thread or the list of threads. The large panel shows both.
struct ThreadPanel: View {
    @Environment(AppModel.self) private var model
    @Binding var wide: Bool

    var body: some View {
        let thread = model.selectedThread.flatMap(model.threads.store.thread)
        VStack(spacing: 0) {
            header(thread)
            Divider().opacity(0.6)
            if wide {
                HStack(spacing: 0) {
                    ThreadListPage(compact: true)
                        .frame(width: Tokens.Size.threadListWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider().opacity(0.6)
                    conversation(thread)
                }
            } else {
                ZStack {
                    switch model.threadPage {
                    case .list:
                        ThreadListPage(compact: false).transition(.move(edge: .leading).combined(with: .opacity))
                    case .conversation:
                        conversation(thread).transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
        .onExitCommand { model.showThreads(false) }
    }

    private func conversation(_ thread: AgentThread?) -> some View {
        Group {
            if let routine = model.selectedRoutine {
                RoutineThreadView(selection: routine).id(routine)
            } else if let thread {
                ThreadConversation(thread: thread).id(thread.id)
            } else {
                ContentUnavailableView("No thread", systemImage: "bubble.left.and.text.bubble.right", description: Text("Press ⌘N to start one."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func title(_ thread: AgentThread?) -> String {
        switch model.selectedRoutine {
        case .routine(let id)?: model.host.plugin(id)?.manifest.name ?? id
        case .noOwner?: "No owner"
        case nil: thread?.title ?? "Threads"
        }
    }

    /// The large panel always shows the conversation, because its list is at the side.
    private var showsConversation: Bool { wide || model.threadPage == .conversation }

    private func header(_ thread: AgentThread?) -> some View {
        HStack(spacing: Tokens.Space.s6) {
            if showsConversation {
                if !wide {
                    PanelIconButton(systemImage: "sidebar.left", help: "All threads") {
                        withAnimation(.snappy) { model.threadPage = .list }
                    }
                }
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text(title(thread)).font(Tokens.Font.rowTitle).lineLimit(1)
                    if let routine = model.selectedRoutine {
                        Text("\(model.routineThread(routine).count) open questions").font(Tokens.Font.meta).foregroundStyle(Theme.muted)
                    } else if let thread {
                        Text(thread.items.isEmpty ? thread.provider.name : "\(thread.provider.name) · \(thread.updatedAt.formatted(.relative(presentation: .named)))")
                            .font(Tokens.Font.meta)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, Tokens.Space.s2)
            } else {
                Text("Threads").font(Tokens.Font.cardTitle).padding(.leading, Tokens.Space.s8)
            }
            Spacer(minLength: Tokens.Space.s8)
            PanelIconButton(systemImage: "square.and.pencil", help: "New thread (⌘N)") {
                withAnimation(.snappy) { model.newThread() }
            }
            PanelIconButton(systemImage: wide ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", help: wide ? "Make smaller" : "Make larger") {
                withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
                    wide.toggle()
                    model.threadPage = .conversation
                }
            }
            PanelIconButton(systemImage: "xmark", help: "Close (Esc)") { model.showThreads(false) }
        }
        .padding(.horizontal, Tokens.Space.s10)
        .padding(.vertical, Tokens.Space.s8)
    }
}

/// A round icon button that shows a fill under the pointer.
struct PanelIconButton: View {
    var systemImage: String
    var help: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Tokens.Font.body.weight(.medium))
                .foregroundStyle(hovering ? .primary : Theme.muted)
                .frame(width: Tokens.Space.s28, height: Tokens.Space.s28)
                .background(Circle().fill(.quaternary).opacity(hovering ? 1 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.snappy(duration: 0.15)) { hovering = inside } }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The threads, newest first, with a search over their titles and last messages.
/// The compact list at the side of the large panel shows one line per thread.
private struct ThreadListPage: View {
    @Environment(AppModel.self) private var model
    var compact: Bool
    @State private var query = ""

    var body: some View {
        let shown = model.threads.store.threads.filter(matches)
        VStack(spacing: Tokens.Space.s8) {
            HStack(spacing: Tokens.Space.s6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.faint)
                TextField("Search threads", text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faint) }.buttonStyle(.plain)
                }
            }
            .font(Tokens.Font.body)
            .padding(Tokens.Padding.field)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.field, style: .continuous).fill(.quinary))
            .padding(.horizontal, compact ? Tokens.Space.s8 : Tokens.Space.s12)
            .padding(.top, Tokens.Space.s10)
            ScrollView {
                LazyVStack(spacing: Tokens.Space.s2) {
                    RoutineRows(compact: compact)
                    if shown.isEmpty {
                        Text(query.isEmpty ? "No threads yet" : "No thread matches").font(Tokens.Font.small).foregroundStyle(Theme.faint)
                            .padding(.top, Tokens.Space.s8)
                    }
                    ForEach(shown) { thread in ThreadRow(thread: thread, compact: compact) }
                }
                .padding(.horizontal, compact ? Tokens.Space.s6 : Tokens.Space.s8)
                .padding(.bottom, Tokens.Space.s10)
            }
            .scrollIndicators(.never)
        }
    }

    private func matches(_ thread: AgentThread) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }
        return [thread.title, thread.preview ?? ""].contains { $0.localizedCaseInsensitiveContains(text) }
    }
}

/// The Routines group: one row per loaded routine with its count of open questions, and a No owner row when an actionable has no routine.
private struct RoutineRows: View {
    @Environment(AppModel.self) private var model
    var compact: Bool

    var body: some View {
        let loaded = Set(model.host.plugins.map(\.id))
        let orphans = RoutineThread.build(routine: nil, actionables: model.host.actionables.all, loaded: loaded)
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("ROUTINES").font(Tokens.Font.caption).tracking(0.6).foregroundStyle(Theme.faint).padding(.horizontal, Tokens.Padding.field.x)
            ForEach(model.host.plugins) { plugin in
                row(.routine(plugin.id), title: plugin.manifest.name, count: model.routineThread(.routine(plugin.id)).count) {
                    PluginMark(plugin: plugin, size: 13).frame(width: 16)
                }
            }
            if !orphans.members.isEmpty {
                row(.noOwner, title: "No owner", count: orphans.count) { Image(systemName: "questionmark.circle").frame(width: 16) }
            }
            Text("THREADS").font(Tokens.Font.caption).tracking(0.6).foregroundStyle(Theme.faint).padding(.horizontal, Tokens.Padding.field.x).padding(.top, Tokens.Space.s8)
        }
    }

    private func row<Mark: View>(_ selection: RoutineSelection, title: String, count: Int, @ViewBuilder mark: () -> Mark) -> some View {
        let selected = model.selectedRoutine == selection
        return Button { model.select(routine: selection) } label: {
            HStack(spacing: Tokens.Space.s8) {
                mark()
                Text(title).font(compact ? Tokens.Font.body : Tokens.Font.rowTitle).lineLimit(1)
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)").font(Tokens.Font.label).foregroundStyle(Theme.muted).padding(Tokens.Padding.pill).background(Theme.pill, in: Capsule())
                }
            }
            .padding(.horizontal, Tokens.Padding.field.x)
            .padding(.vertical, Tokens.Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.field, style: .continuous).fill(.quaternary).opacity(selected ? 1 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ThreadRow: View {
    @Environment(AppModel.self) private var model
    var thread: AgentThread
    var compact: Bool
    @State private var hovering = false

    var body: some View {
        let selected = model.selectedRoutine == nil && model.selectedThread == thread.id
        let running = model.threads.isRunning(thread.id)
        Button { model.select(thread: thread.id) } label: {
            HStack(alignment: .top, spacing: Tokens.Space.s10) {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    Text(thread.title).font(compact ? Tokens.Font.body.weight(selected ? .medium : .regular) : Tokens.Font.rowTitle).lineLimit(1)
                    if !compact {
                        Text(thread.preview ?? "No message yet")
                            .font(Tokens.Font.meta)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if running {
                    ProgressView().controlSize(.mini)
                } else if hovering {
                    Button { withAnimation(.snappy) { model.delete(thread: thread.id) } } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Delete the thread")
                } else {
                    Text(thread.updatedAt.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                        .font(Tokens.Font.meta)
                        .foregroundStyle(Theme.faint)
                }
            }
            .padding(.horizontal, Tokens.Padding.field.x)
            .padding(.vertical, compact ? Tokens.Space.s6 : Tokens.Padding.field.y)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.field, style: .continuous).fill(.quaternary).opacity(selected ? 1 : hovering ? 0.5 : 0))
            .help(compact ? thread.preview ?? thread.title : "")
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) { model.delete(thread: thread.id) }
        }
    }
}

extension AgentThread {
    /// The last message of the thread, yours or the agent's.
    var preview: String? {
        items.last { $0.kind == .message || $0.kind == .user }?.text
    }
}
