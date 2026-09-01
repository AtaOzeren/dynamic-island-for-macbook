import NotchFlowProviders

/// The one line of the Apple Clock integration that differs between build
/// configurations.
///
/// Lives in the app target for the same reason `makeMusicProvider(gate:)` does:
/// Xcode's active compilation conditions never reach Swift package targets, so
/// an `#if DIRECT_BUILD` inside `NotchFlowProviders` would be dead code in both
/// configurations and the Accessibility path would link into the App Store
/// binary regardless.
///
/// The App Store build gets no mirror. Reading another application's
/// accessibility tree is not available to a sandboxed app, and NotchFlow's own
/// `TimerProvider` remains the timer there.
@MainActor
func makeAppleClockMirror(timerProvider: TimerProvider) -> AppleClockMirror? {
    #if DIRECT_BUILD
        AppleClockMirror(provider: timerProvider)
    #else
        nil
    #endif
}
