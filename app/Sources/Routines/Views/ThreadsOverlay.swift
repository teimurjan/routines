import RoutinesKit
import SwiftUI

/// The floating button at the bottom right of the window. It morphs into the glass thread panel.
struct ThreadsOverlay: View {
    @Environment(AppModel.self) private var model
    /// The size of the content area beside the sidebar. The large panel fills it.
    var room: CGSize
    @Namespace private var glass
    @State private var wide = false

    var body: some View {
        let inset = Tokens.Size.floatInset
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.popover, style: .continuous)
        let tallest = max(room.height - inset * 2 - Tokens.Space.s28, Tokens.Size.floatButton)
        let widest = max(room.width - inset * 2, Tokens.Size.floatButton)
        GlassGroup {
            if model.threadsOpen {
                ThreadPanel(wide: $wide)
                    .frame(
                        width: wide ? widest : min(Tokens.Size.threadPanelWidth, widest),
                        height: wide ? tallest : min(Tokens.Size.threadPanelHeight, tallest)
                    )
                    .clipShape(shape)
                    .onClickOutside { model.showThreads(false) }
                    .glassSurface(shape, frosted: true)
                    .glassID("threads", in: glass)
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            } else {
                ThreadsButton()
                    .glassID("threads", in: glass)
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .padding(inset)
    }
}

/// A round glass button with the count of running threads and a ring that turns while the agent works.
private struct ThreadsButton: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let running = model.threads.runningCount
        Button { model.showThreads(true) } label: {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(Tokens.Font.headline)
                .foregroundStyle(.primary)
                .frame(width: Tokens.Size.floatButton, height: Tokens.Size.floatButton)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassSurface(Circle(), interactive: true)
        .overlay { if running > 0 { RunningRing() } }
        .overlay(alignment: .topTrailing) {
            if running > 0 {
                Text("\(running)")
                    .font(Tokens.Font.label)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, Tokens.Space.s6)
                    .padding(.vertical, Tokens.Space.s2)
                    .background(Color.accentColor, in: Capsule())
                    .offset(x: Tokens.Space.s4, y: -Tokens.Space.s4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(hovering ? 1.06 : 1)
        .onHover { inside in withAnimation(.snappy) { hovering = inside } }
        .animation(.snappy, value: running)
        .help("Threads (⌘J)")
        .accessibilityLabel("Threads")
    }
}

private struct RunningRing: View {
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.3)
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: Tokens.Space.s2, lineCap: .round))
            .padding(-Tokens.Space.s3)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { turning = true }
            }
            .allowsHitTesting(false)
    }
}
