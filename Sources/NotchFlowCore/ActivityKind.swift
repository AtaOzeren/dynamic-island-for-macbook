public enum ActivityKind: Hashable, CaseIterable, Sendable {
    case music
    case timer
    case recording
    case charging
    case aiAgent
    case fileTransfer
    /// The one-off explanation of a CPU watchdog episode the user did not see.
    case watchdogNotice
}
