/// What a click on an activity's compact or expanded view offers to do, per the
/// optional primary action in `docs/05-activity-model.md`.
///
/// This describes the affordance — the label and glyph the expanded row draws —
/// rather than carrying the closure that performs it. Keeping the descriptor a
/// value type is what lets `Activity` stay `Sendable` and `ExpandedRow` stay
/// `Equatable`, so the rows a given active set produces can be asserted on
/// directly; dispatching the click is the presenter's job, not the model's.
public struct PrimaryAction: Equatable, Sendable {
    /// The affordance's user-visible title, e.g. "Open Spotify".
    public let title: String
    /// An SF Symbol drawn alongside the title.
    public let symbolName: String

    public init(title: String, symbolName: String = "arrow.up.forward") {
        self.title = title
        self.symbolName = symbolName
    }
}
