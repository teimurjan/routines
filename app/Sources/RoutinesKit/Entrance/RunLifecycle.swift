/// The runs of one routine: idle, running, or running with one run queued (FR-016).
public enum RunLifecycle: Equatable, Sendable {
    case idle, running, queued

    public enum Event: Sendable { case trigger, ended }
    public enum Effect: Equatable, Sendable { case start, none }

    public func next(on event: Event) -> (RunLifecycle, Effect) {
        switch (self, event) {
        case (.idle, .trigger): (.running, .start)
        case (.running, .trigger), (.queued, .trigger): (.queued, .none)
        case (.running, .ended), (.idle, .ended): (.idle, .none)
        case (.queued, .ended): (.running, .start)
        }
    }
}
