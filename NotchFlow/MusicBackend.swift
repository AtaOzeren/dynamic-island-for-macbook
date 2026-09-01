import NotchFlowCore
import NotchFlowProviders

/// Selects the strongest music backend the current build and macOS release can
/// use.
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
/// macOS 15.4 restricted MediaRemote metadata to Apple-signed processes. Direct
/// builds therefore use the same scriptable Spotify/Music path on newer macOS
/// releases, while older systems retain system-wide MediaRemote coverage.
@MainActor
func makeMusicProvider(gate: MusicAutomationGate) -> any MusicProvider {
    #if DIRECT_BUILD
        if #available(macOS 15.4, *) {
            AppleScriptMusicProvider(
                gate: gate,
                artworkLoader: URLSessionArtworkDataLoader()
            )
        } else {
            MediaRemoteMusicProvider()
        }
    #else
        AppleScriptMusicProvider(gate: gate)
    #endif
}

/// The permission rows the Activities pane should show for the selected
/// backend.
///
/// It branches beside `makeMusicProvider` rather than inside the pane so the two
/// answers cannot disagree: a backend that needs no Apple Events must not offer
/// to request them, and both facts come from the same availability branch.
@MainActor
func makeMusicAutomationAccess(gate: MusicAutomationGate) -> [MusicAutomationAccess] {
    #if DIRECT_BUILD
        if #available(macOS 15.4, *) {
            gate.access()
        } else {
            []
        }
    #else
        gate.access()
    #endif
}

/// Rows shown before the asynchronous TCC status lookup completes.
///
/// Constructing these values performs no Apple Events call, so application
/// launch can always reach its menu bar scene even when the consent service is
/// slow or waiting on a stale prompt.
@MainActor
func makePendingMusicAutomationAccess() -> [MusicAutomationAccess] {
    #if DIRECT_BUILD
        if #available(macOS 15.4, *) {
            MusicPlayerTarget.allCases.map {
                MusicAutomationAccess(target: $0, status: .notDetermined)
            }
        } else {
            []
        }
    #else
        MusicPlayerTarget.allCases.map {
            MusicAutomationAccess(target: $0, status: .notDetermined)
        }
    #endif
}
