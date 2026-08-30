import NotchFlowCore
import NotchFlowProviders

/// The one line that differs between build configurations.
///
/// It lives in the app target rather than in `NotchFlowProviders` because
/// Xcode's active compilation conditions never reach Swift package targets: an
/// `#if DIRECT_BUILD` inside the package is dead code in both configurations,
/// and the private-framework backend would be linked into the App Store binary
/// regardless. Keeping the branch here is what makes the todo-21 symbol guard
/// meaningful — see `docs/06-activity-providers.md`.
///
/// Configurations that define neither condition (`Debug`, `Release`) get the
/// App Store backend: the private-framework path is opt-in, never a default.
/// The gate is ignored by the Direct build on purpose: MediaRemote reads the
/// system's own now-playing state and sends no Apple Events, so there is no
/// permission for it to be gated on.
@MainActor
func makeMusicProvider(gate: MusicAutomationGate) -> any MusicProvider {
    #if DIRECT_BUILD
        MediaRemoteMusicProvider()
    #else
        AppleScriptMusicProvider(gate: gate)
    #endif
}

/// The permission rows the Activities pane should show, which is none in the
/// Direct build.
///
/// It branches beside `makeMusicProvider` rather than inside the pane so the two
/// answers cannot disagree: a build whose backend needs no Apple Events must not
/// offer to request them, and both facts now come from the same `#if`.
@MainActor
func makeMusicAutomationAccess(gate: MusicAutomationGate) -> [MusicAutomationAccess] {
    #if DIRECT_BUILD
        []
    #else
        gate.access()
    #endif
}
