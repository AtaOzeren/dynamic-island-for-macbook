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
@MainActor
func makeMusicProvider() -> any MusicProvider {
    #if DIRECT_BUILD
        MediaRemoteMusicProvider()
    #else
        AppleScriptMusicProvider()
    #endif
}
