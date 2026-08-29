import NotchFlowCore

/// Presents one of the concrete providers to `ActivityProviderRegistry` under
/// its settings identifier.
///
/// The concrete providers each emit an optional — an activity, or `nil` for
/// "there is nothing to show" — which is the natural shape when exactly one call
/// site is listening and already knows whose absence it is reading. The registry
/// multiplexes several providers onto one observer, where that shape loses the
/// identity teardown needs, so the translation happens here rather than by
/// rewriting four providers to carry an identity they only need at this seam.
///
/// The ended identity is the last one emitted rather than a constant, because
/// the registration cannot know it any other way: `RecordingActivity`'s identity
/// depends on its source and `MusicActivity`'s belongs to the activity type. You
/// can only end what you started, so remembering it is both sufficient and
/// exactly right.
@MainActor
public final class ActivityProviderRegistration<Emitted: Activity>: ActivityProvider {
    /// Starts the wrapped provider, handing it an observer of *its* optional
    /// shape. The closure is what keeps this type from needing to know which
    /// provider it wraps.
    public typealias Start = @MainActor (@escaping @MainActor (Emitted?) -> Void) -> Void
    public typealias Stop = @MainActor () -> Void

    public let identifier: ActivityProviderIdentifier
    private let start: Start
    private let stop: Stop
    private var observer: ActivityObserver?
    private var liveIdentity: ActivityIdentity?

    public init(
        identifier: ActivityProviderIdentifier,
        start: @escaping Start,
        stop: @escaping Stop
    ) {
        self.identifier = identifier
        self.start = start
        self.stop = stop
    }

    public func startObserving(_ observer: @escaping ActivityObserver) {
        self.observer = observer
        start { [weak self] activity in
            self?.emit(activity)
        }
    }

    /// Stopping does not synthesize an end. Whoever stopped this provider is
    /// responsible for the activities it left behind — the registry ends them on
    /// a disable, and on a full teardown there is no island left to clear.
    public func stopObserving() {
        observer = nil
        liveIdentity = nil
        stop()
    }

    private func emit(_ activity: Emitted?) {
        guard let observer else { return }

        guard let activity else {
            guard let ended = liveIdentity else { return }
            liveIdentity = nil
            observer(.ended(ended))
            return
        }

        /// An identity that changes without passing through `nil` is a
        /// substitution, not an update, so the old one is ended before the new
        /// one starts. No V1 provider does this, but the registry's bookkeeping
        /// would otherwise leak the old identity and the manager would keep
        /// rendering it beside its replacement.
        if let ended = liveIdentity, ended != activity.identity {
            observer(.ended(ended))
        }

        liveIdentity = activity.identity
        observer(.active(activity))
    }
}

public extension ActivityProviderRegistration where Emitted == MusicActivity {
    static func music(_ provider: any MusicProvider) -> Self {
        Self(
            identifier: .music,
            start: { emit in
                provider.startObserving { nowPlaying in
                    emit(musicActivity(for: nowPlaying))
                }
            },
            stop: { provider.stopObserving() }
        )
    }

}

public extension ActivityProviderRegistration where Emitted == TimerActivity {
    static func timer(_ provider: TimerProvider) -> Self {
        Self(
            identifier: .timer,
            start: { emit in provider.startObserving(emit) },
            stop: { provider.stopObserving() }
        )
    }

}

public extension ActivityProviderRegistration where Emitted == RecordingActivity {
    /// The identifier follows the provider's own source, so the two recording
    /// registrations cannot be wired to each other's settings switch.
    static func recording(_ provider: RecordingProvider) -> Self {
        Self(
            identifier: provider.source == .screen ? .screenRecording : .audioRecording,
            start: { emit in provider.startObserving(emit) },
            stop: { provider.stopObserving() }
        )
    }

}

public extension ActivityProviderRegistration where Emitted == ChargingActivity {
    static func charging(_ provider: ChargingProvider) -> Self {
        Self(
            identifier: .charging,
            start: { emit in provider.startObserving(emit) },
            stop: { provider.stopObserving() }
        )
    }
}
