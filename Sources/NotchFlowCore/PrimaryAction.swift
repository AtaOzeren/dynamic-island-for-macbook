/// What a click on an activity's compact or expanded view offers to do, per the
/// optional primary action in `docs/05-activity-model.md`.
///
/// This describes the affordance — the label and glyph the expanded row draws —
/// rather than carrying the closure that performs it. Keeping the descriptor a
/// value type is what lets `Activity` stay `Sendable` and `ExpandedRow` stay
/// `Equatable`, so the rows a given active set produces can be asserted on
/// directly; dispatching the click is the presenter's job, not the model's.
public struct PrimaryAction: Equatable, Sendable {
    /// What executing this action does, stated as data. Core can name the
    /// intent but cannot perform it — opening an application needs AppKit —
    /// so the composition root reads this value and routes it to an executor.
    /// `nil` marks an affordance with no machine-readable effect yet, which
    /// renders exactly as before and dispatches to nothing.
    public enum Intent: Equatable, Sendable {
        /// Activate the application the activity is about, by the name the
        /// system reports for it (e.g. "Spotify").
        case openApplicationNamed(String)
        /// Activate an AI agent's application.
        case openAgentApplication(IPCAgentID)
        /// Stop and clear the timer — how an expired countdown is acknowledged.
        case stopTimer
        /// Pause the running timer.
        case pauseTimer
        /// Resume the paused timer.
        case resumeTimer
    }

    /// The affordance's user-visible title, e.g. "Open Spotify".
    public let title: String
    /// An SF Symbol drawn alongside the title.
    public let symbolName: String
    /// What a click asks the composition root to do.
    public let intent: Intent?

    public init(title: String, symbolName: String = "arrow.up.forward", intent: Intent? = nil) {
        self.title = title
        self.symbolName = symbolName
        self.intent = intent
    }
}
