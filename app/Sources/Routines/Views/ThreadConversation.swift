import RoutinesKit
import SwiftUI

/// The open thread. It follows new output while you are at the bottom, and a button takes you back there.
struct ThreadConversation: View {
    @Environment(AppModel.self) private var model
    var thread: AgentThread
    @State private var atBottom = true
    private let bottom = "bottom"

    var body: some View {
        let running = model.threads.isRunning(thread.id)
        let segments = thread.segments
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    // Not lazy: estimated row heights under a bottom anchor looped the layout and froze the app.
                    VStack(alignment: .leading, spacing: Tokens.Space.s16) {
                        ForEach(problems, id: \.self) { problem in Banner(text: problem) }
                        if thread.items.isEmpty { EmptyThread(threadId: thread.id) }
                        ForEach(segments) { segment in
                            SegmentView(segment: segment, live: running && segment.id == segments.last?.id, workspace: model.host.paths.workspaceDir)
                        }
                        if running {
                            WorkingIndicator(since: thread.items.last { $0.kind == .user }?.date ?? thread.updatedAt)
                        } else {
                            TouchedRoutines(ids: thread.touchedPlugins)
                        }
                        Color.clear.frame(height: Tokens.Space.s1).id(bottom)
                    }
                    .padding(.horizontal, Tokens.Space.s18)
                    .padding(.vertical, Tokens.Space.s16)
                }
                .defaultScrollAnchor(.bottom)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - Tokens.Space.s28 * 2
                } action: { _, isAtBottom in
                    atBottom = isAtBottom
                }
                .onChange(of: thread.items) {
                    guard atBottom else { return }
                    withAnimation(.snappy) { proxy.scrollTo(bottom, anchor: .bottom) }
                }
                .overlay(alignment: .bottom) { jumpButton(proxy) }
            }
            ThreadComposer(thread: thread, running: running)
        }
    }

    /// The animation stays on this button, so a change of `atBottom` does not animate the messages.
    private func jumpButton(_ proxy: ScrollViewProxy) -> some View {
        ZStack {
            if !atBottom {
                Button { withAnimation(.snappy) { proxy.scrollTo(bottom, anchor: .bottom) } } label: {
                    Image(systemName: "arrow.down")
                        .font(Tokens.Font.body.weight(.semibold))
                        .frame(width: Tokens.Space.s28, height: Tokens.Space.s28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassSurface(Circle(), interactive: true)
                .padding(.bottom, Tokens.Space.s10)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
                .help("Jump to the latest message")
            }
        }
        .animation(.snappy, value: atBottom)
    }

    private var problems: [String] {
        let status = model.threads.status
        let notReady = status.flatMap { $0.ready ? nil : $0.detail }
        return [model.host.workspaceProblem, notReady, status?.warning].compactMap { $0 }
    }
}

private struct SegmentView: View {
    var segment: ThreadSegment
    /// The last segment of a running turn shows its current step.
    var live: Bool
    var workspace: String

    var body: some View {
        switch segment {
        case .steps(let steps): StepsGroup(steps: steps, live: live, workspace: workspace)
        case .entry(let item):
            switch item.kind {
            case .user: UserMessage(item: item)
            case .error: ErrorMessage(text: item.text)
            default: AgentMessage(item: item)
            }
        }
    }
}

private struct UserMessage: View {
    var item: ThreadItem

    var body: some View {
        VStack(alignment: .trailing, spacing: Tokens.Space.s6) {
            if let references = item.references, !references.isEmpty {
                FlowChips(references: references)
            }
            Text(item.text)
                .font(Tokens.Font.bodyLarge)
                .textSelection(.enabled)
                .padding(.horizontal, Tokens.Space.s12)
                .padding(.vertical, Tokens.Space.s8)
                .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: Tokens.Radius.bubble, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, Tokens.Space.s28 * 2)
    }
}

/// The chips of a sent message, trailing and wrapped onto more lines when they do not fit.
private struct FlowChips: View {
    var references: [ItemReference]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tokens.Space.s4) { chips }
            VStack(alignment: .trailing, spacing: Tokens.Space.s4) { chips }
        }
    }

    private var chips: some View {
        ForEach(references, id: \.self) { reference in ReferenceChip(reference: reference) }
    }
}

private struct AgentMessage: View {
    var item: ThreadItem
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            MessageText(text: item.text)
            HStack(spacing: Tokens.Space.s8) {
                CopyButton(text: item.text)
                Text(item.date.formatted(date: .omitted, time: .shortened)).font(Tokens.Font.meta).foregroundStyle(Theme.faint)
            }
            .opacity(hovering ? 1 : 0)
        }
        .onHover { inside in withAnimation(.snappy(duration: 0.15)) { hovering = inside } }
    }
}

private struct ErrorMessage: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.s8) {
            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(Theme.danger)
            Text(text).font(Tokens.Font.small).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.s10)
        .background(Theme.danger.opacity(Tokens.Opacity.tint), in: RoundedRectangle(cornerRadius: Tokens.Radius.track, style: .continuous))
    }
}

/// The steps between two messages in one line. A click opens each step and its output.
private struct StepsGroup: View {
    var steps: [ThreadItem]
    var live: Bool
    var workspace: String
    @State private var open = false

    var body: some View {
        let current = steps.last { $0.state == .running }
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(spacing: Tokens.Space.s6) {
                    if current != nil {
                        ProgressView().controlSize(.mini)
                    } else if steps.contains(where: { $0.state == .failed }) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.warning)
                    } else {
                        Image(systemName: "checkmark.circle").foregroundStyle(Theme.faint)
                    }
                    Text(Self.summary(steps)).foregroundStyle(Theme.muted)
                    Image(systemName: "chevron.right")
                        .font(Tokens.Font.micro)
                        .foregroundStyle(Theme.faint)
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Spacer(minLength: 0)
                }
                .font(Tokens.Font.meta)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                    ForEach(steps) { step in StepRow(item: step, workspace: workspace) }
                }
                .padding(.leading, Tokens.Space.s10)
                .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: Tokens.Space.s1) }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if live, let step = current ?? steps.last {
                StepRow(item: step, workspace: workspace).transition(.opacity)
            }
        }
    }

    /// For example "Ran 3 commands, made 2 edits".
    static func summary(_ steps: [ThreadItem]) -> String {
        let count = { (kind: ThreadItem.Kind) in steps.count { $0.kind == kind } }
        let phrase = { (number: Int, verb: String, noun: String) in number == 0 ? nil : "\(verb) \(number) \(noun)\(number == 1 ? "" : "s")" }
        let parts = [
            phrase(count(.command), "ran", "command"),
            phrase(count(.fileChange), "made", "edit"),
            phrase(count(.tool), "used", "tool"),
            count(.reasoning) > 0 ? "thought" : nil,
        ].compactMap { $0 }
        let text = parts.joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// One command, file change, tool call or thought. Its output opens on a click.
private struct StepRow: View {
    var item: ThreadItem
    var workspace: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack(spacing: Tokens.Space.s6) {
                    Image(systemName: icon).frame(width: Tokens.Space.s16).foregroundStyle(Theme.muted)
                    Text(title).font(Tokens.Font.mono.monospaced()).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    switch item.state {
                    case .running: ProgressView().controlSize(.mini)
                    case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.danger)
                    case .done: EmptyView()
                    }
                    if !item.text.isEmpty {
                        Image(systemName: "chevron.right").font(Tokens.Font.micro).foregroundStyle(Theme.faint).rotationEffect(.degrees(open ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.text.isEmpty)
            if open, !item.text.isEmpty {
                Text(item.text)
                    .font(item.kind == .reasoning ? Tokens.Font.small.italic() : Tokens.Font.mono.monospaced())
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
                    .padding(Tokens.Padding.field)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous).fill(.quinary))
            }
        }
    }

    /// Paths in the workspace show from the workspace folder.
    private var title: String {
        if item.kind == .reasoning { return "Thinking" }
        return item.title.replacingOccurrences(of: workspace + "/", with: "")
    }

    private var icon: String {
        switch item.kind {
        case .command: "terminal"
        case .fileChange: "pencil"
        case .reasoning: "brain"
        default: "wrench.and.screwdriver"
        }
    }
}

private struct WorkingIndicator: View {
    var since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(since)))
            HStack(spacing: Tokens.Space.s8) {
                Image(systemName: "sparkle").foregroundStyle(Color.accentColor).symbolEffect(.pulse)
                Text("Working").modifier(Shimmer())
                Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))).monospacedDigit().foregroundStyle(Theme.faint)
            }
            .font(Tokens.Font.small)
            .foregroundStyle(Theme.muted)
        }
    }
}

/// The start of a thread, with ideas that fill the composer.
private struct EmptyThread: View {
    @Environment(AppModel.self) private var model
    var threadId: String
    private static let ideas = [
        ("plus.square.on.square", "Make a routine that checks my site every hour and tells me when it is down."),
        ("stethoscope", "Why did the last run of my routine fail?"),
        ("calendar", "Change a routine, so it runs only on weekdays."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s12) {
            Image(systemName: "sparkles")
                .font(Tokens.Font.display)
                .foregroundStyle(Color.accentColor.gradient)
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text("What should we build?").font(Tokens.Font.title)
                Text("The agent makes and changes routines in your workspace, and it reads their runs.")
                    .font(Tokens.Font.body)
                    .foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                ForEach(Self.ideas, id: \.1) { icon, text in IdeaButton(icon: icon, text: text) { use(text) } }
            }
            Label("Command-click an item in a routine to ask about it.", systemImage: "command")
                .font(Tokens.Font.meta)
                .foregroundStyle(Theme.faint)
        }
        .padding(.top, Tokens.Space.s12)
    }

    private func use(_ text: String) {
        model.drafts[threadId, default: ThreadDraft()].text = text
        model.composerFocus += 1
    }
}

private struct IdeaButton: View {
    var icon: String
    var text: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s10) {
                Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: Tokens.Space.s16)
                Text(text).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left").font(Tokens.Font.micro).foregroundStyle(Theme.faint).opacity(hovering ? 1 : 0)
            }
            .font(Tokens.Font.body)
            .padding(Tokens.Padding.field)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.field, style: .continuous).fill(.quaternary).opacity(hovering ? 1 : 0.55))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.snappy(duration: 0.15)) { hovering = inside } }
    }
}

/// The routines that the thread changed, each with a button that opens it.
private struct TouchedRoutines: View {
    @Environment(AppModel.self) private var model
    var ids: [String]

    var body: some View {
        let plugins = ids.compactMap { model.host.plugin($0) }
        if !plugins.isEmpty {
            HStack(spacing: Tokens.Space.s6) {
                ForEach(plugins) { plugin in
                    Button { model.open(pluginId: plugin.id) } label: {
                        HStack(spacing: Tokens.Space.s6) {
                            PluginMark(plugin: plugin, size: 13)
                            Text("Open \(plugin.manifest.name)")
                            if plugin.problem != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
                        }
                        .font(Tokens.Font.button)
                        .padding(Tokens.Padding.button)
                        .background(Capsule().fill(.quaternary))
                    }
                    .buttonStyle(.plain)
                    .help(plugin.problem ?? plugin.manifest.description)
                }
            }
        }
    }
}

/// Copies the text and shows a check for a moment.
struct CopyButton: View {
    var text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            withAnimation(.snappy) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.snappy) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
                .font(Tokens.Font.meta)
                .foregroundStyle(copied ? Theme.success : Theme.muted)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : "Copy")
    }
}

/// An item that a message asks about. A click opens it in its routine.
struct ReferenceChip: View {
    @Environment(AppModel.self) private var model
    var reference: ItemReference
    var remove: (() -> Void)?

    var body: some View {
        HStack(spacing: Tokens.Space.s4) {
            Button { model.open(pluginId: reference.pluginId, itemId: reference.cardId) } label: {
                HStack(spacing: Tokens.Space.s4) {
                    if let plugin = model.host.plugin(reference.pluginId) { PluginMark(plugin: plugin, size: 11) }
                    Text(reference.title).lineLimit(1).truncationMode(.tail)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the item in \(model.host.plugin(reference.pluginId)?.manifest.name ?? reference.pluginId)")
            if let remove {
                Button(action: remove) { Image(systemName: "xmark").font(Tokens.Font.micro).foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain)
                    .help("Remove")
            }
        }
        .font(Tokens.Font.caption)
        .frame(maxWidth: Tokens.Size.threadPanelWidth / 2, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .padding(Tokens.Padding.pill)
        .background(Capsule().fill(.quaternary))
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.35)))
    }
}
