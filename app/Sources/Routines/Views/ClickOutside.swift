import AppKit
import SwiftUI

extension View {
    /// Calls the action on a click in the same window outside this view. The click still reaches its target.
    /// A click with Command or Control is ignored, so it can add an item to the open thread.
    func onClickOutside(perform action: @escaping () -> Void) -> some View {
        modifier(ClickOutside(action: action))
    }
}

private struct ClickOutside: ViewModifier {
    var action: () -> Void
    @State private var tracker = ClickTracker()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { tracker.frame = $0 }
            .background(WindowReader(tracker: tracker))
            .onAppear { tracker.start(action) }
            .onDisappear { tracker.stop() }
    }
}

@MainActor
private final class ClickTracker {
    var frame = CGRect.zero
    weak var window: NSWindow?
    private var monitor: Any?
    private var action: () -> Void = {}

    func start(_ action: @escaping () -> Void) {
        stop()
        self.action = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // The action runs after the click, so the panel does not close while the event is still in flight.
            if let self, self.isOutside(event) { Task { [weak self] in self?.action() } }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// A click in a sheet or another window is not outside, because it lands in a different window.
    private func isOutside(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, let root = window.contentView else { return false }
        guard event.modifierFlags.isDisjoint(with: [.command, .control]) else { return false }
        let point = root.convert(event.locationInWindow, from: nil)
        let top = root.isFlipped ? point.y : root.bounds.height - point.y
        return !frame.contains(CGPoint(x: point.x, y: top))
    }
}

/// Gives the tracker the window of the view.
private struct WindowReader: NSViewRepresentable {
    var tracker: ClickTracker

    func makeNSView(context: Context) -> NSView { ReaderView(tracker: tracker) }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class ReaderView: NSView {
        let tracker: ClickTracker

        init(tracker: ClickTracker) {
            self.tracker = tracker
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tracker.window = window
        }
    }
}
