/// The providers a user can individually switch off, one case per
/// `providers.*.enabled` row of the settings table in
/// `docs/08-settings-and-localization.md`.
///
/// This is deliberately not `ActivityKind`. Kind answers "what does this
/// activity look like on the island", and the two recording sources share one
/// kind because they render identically; enablement answers "did the user ask
/// for this observation to run", and screen recording and microphone recording
/// are separately switchable because they watch different signals and carry
/// different privacy weight. Keying enablement on kind would silently fuse those
/// two switches into one.
///
/// The AI agents are absent for the same reason from the other direction: they
/// are gated per agent and per event class (todo 58), which is a finer control
/// than one switch per provider.
public enum ActivityProviderIdentifier: Hashable, CaseIterable, Sendable {
    case music
    case timer
    case screenRecording
    case audioRecording
    case charging

    /// What the Activities pane calls this switch, kept beside the enum on the
    /// same rationale as `AIEventClass.displayName`: adding a case forces the
    /// label, so a new provider cannot ship an unlabelled row.
    public var displayName: String {
        switch self {
        case .music: "Music"
        case .timer: "Timers and stopwatches"
        case .screenRecording: "Screen recording"
        case .audioRecording: "Microphone recording"
        case .charging: "Charging"
        }
    }

    /// Why a user would switch this off, in one line. The two recording rows
    /// carry different privacy weight and the comment above explains why they
    /// are separate switches — the pane has to say that out loud, or the split
    /// reads as an accident.
    public var caption: String {
        switch self {
        case .music: "Now playing, from Apple Music, Spotify, and system media."
        case .timer: "Countdowns and elapsed time."
        case .screenRecording: "A reminder while your screen is being captured."
        case .audioRecording: "A reminder while your microphone is in use."
        case .charging: "Battery level when you plug in or unplug."
        }
    }
}
