import NotchFlowCore

/// Builds the registry holding every V1 activity provider and connects it to the
/// manager.
///
/// This is the one place that knows the full provider list, which is what makes
/// "each provider is started only when its setting is enabled" a single
/// invariant rather than five call sites that must agree. The music backend
/// arrives as a parameter because only the app target can choose it — see
/// `MusicBackend.swift` — and the system observers are constructed here because
/// nothing above this layer should have to name them.
@MainActor
public enum ProviderComposition {
    public static func makeRegistry(
        musicProvider: any MusicProvider,
        timerProvider: TimerProvider,
        enabledIdentifiers: Set<ActivityProviderIdentifier>
    ) -> ActivityProviderRegistry {
        ActivityProviderRegistry(
            providers: [
                ActivityProviderRegistration.music(musicProvider),
                ActivityProviderRegistration.timer(timerProvider),
                ActivityProviderRegistration.recording(
                    RecordingProvider(source: .screen, sessions: SystemScreenRecordingObserver())
                ),
                ActivityProviderRegistration.recording(
                    RecordingProvider(source: .audio, sessions: SystemAudioRecordingObserver())
                ),
                ActivityProviderRegistration.charging(
                    ChargingProvider(source: SystemPowerSourceObserver())
                ),
            ],
            enabledIdentifiers: enabledIdentifiers
        )
    }
}

extension ActivityProviderRegistry {
    /// Starts every enabled provider, routing what they emit into the manager.
    ///
    /// `register` rather than `update` for an active emission because the
    /// manager already preserves the original registration time when the
    /// identity is one it holds — so one call covers both first appearance and
    /// every subsequent tick, and an activity re-registered after a disable
    /// still orders correctly against the ones that never went away.
    public func startObserving(into manager: ActivityManager) {
        startObserving { [weak manager] emission in
            switch emission {
            case .active(let activity):
                manager?.register(activity)
            case .ended(let identity):
                manager?.end(identity)
            }
        }
    }
}
