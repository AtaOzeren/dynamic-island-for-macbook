import KerNotchCore
import KerNotchProviders

/// Selects the strongest music backend the running macOS release allows.
///
/// macOS 15.4 restricted MediaRemote metadata to Apple-signed processes, so
/// newer releases use the scriptable Spotify/Music path, while older systems
/// keep system-wide MediaRemote coverage. It lives in the app target because
/// the MediaRemote backend is private-framework code that the provider package
/// deliberately does not carry — see `docs/06-activity-providers.md`.
@MainActor
func makeMusicProvider(gate: MusicAutomationGate) -> any MusicProvider {
    if #available(macOS 15.4, *) {
        AppleScriptMusicProvider(
            gate: gate,
            artworkLoader: URLSessionArtworkDataLoader()
        )
    } else {
        MediaRemoteMusicProvider()
    }
}

/// The permission rows the Activities pane should show for the selected
/// backend.
///
/// It branches beside `makeMusicProvider` rather than inside the pane so the two
/// answers cannot disagree: a backend that needs no Apple Events must not offer
/// to request them, and both facts come from the same availability branch.
@MainActor
func makeMusicAutomationAccess(gate: MusicAutomationGate) -> [MusicAutomationAccess] {
    if #available(macOS 15.4, *) {
        gate.access()
    } else {
        []
    }
}

/// Rows shown before the asynchronous TCC status lookup completes.
///
/// Constructing these values performs no Apple Events call, so application
/// launch can always reach its menu bar scene even when the consent service is
/// slow or waiting on a stale prompt.
@MainActor
func makePendingMusicAutomationAccess() -> [MusicAutomationAccess] {
    if #available(macOS 15.4, *) {
        MusicPlayerTarget.allCases.map {
            MusicAutomationAccess(target: $0, status: .notDetermined)
        }
    } else {
        []
    }
}
