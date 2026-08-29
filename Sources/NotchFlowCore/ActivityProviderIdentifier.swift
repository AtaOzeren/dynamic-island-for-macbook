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
}
