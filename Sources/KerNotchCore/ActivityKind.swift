public enum ActivityKind: Hashable, CaseIterable, Sendable {
    case music
    case timer
    case recording
    case charging
    case aiAgent
    case fileTransfer
    /// The one-off explanation of a CPU watchdog episode the user did not see.
    case watchdogNotice
    /// A Discord voice call, which stands in for the microphone indicator while
    /// the Discord integration is on.
    case discordCall
}
