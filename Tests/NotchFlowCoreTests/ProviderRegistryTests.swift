import Testing

@testable import NotchFlowCore

@Suite("ProviderRegistry")
@MainActor
struct ProviderRegistryTests {
    @Test("starts every enabled provider")
    func startsRegisteredProviders() {
        let firstProvider = FakeActivityProvider(identifier: .timer)
        let secondProvider = FakeActivityProvider(identifier: .music)
        let registry = ActivityProviderRegistry(providers: [firstProvider, secondProvider])

        registry.startObserving { _ in }

        #expect(firstProvider.startCount == 1)
        #expect(secondProvider.startCount == 1)
    }

    @Test("forwards emitted activities while observing")
    func forwardsActivities() {
        let provider = FakeActivityProvider(identifier: .timer)
        let registry = ActivityProviderRegistry(providers: [provider])
        var receivedIdentities: [ActivityIdentity] = []

        registry.startObserving { emission in
            receivedIdentities.append(emission.identity)
        }
        provider.emit(.active(StubProviderActivity(identity: ActivityIdentity("timer.focus"))))

        #expect(receivedIdentities == [ActivityIdentity("timer.focus")])
    }

    @Test("stops every provider and suppresses later emissions")
    func stopsProvidersAndEmissions() {
        let firstProvider = FakeActivityProvider(identifier: .timer)
        let secondProvider = FakeActivityProvider(identifier: .music)
        let registry = ActivityProviderRegistry(providers: [firstProvider, secondProvider])
        var receivedCount = 0

        registry.startObserving { _ in
            receivedCount += 1
        }
        firstProvider.emit(.active(StubProviderActivity(identity: ActivityIdentity("timer.before-stop"))))

        registry.stopObserving()
        firstProvider.emit(.active(StubProviderActivity(identity: ActivityIdentity("timer.after-stop"))))
        secondProvider.emit(.active(StubProviderActivity(identity: ActivityIdentity("music.after-stop"))))

        #expect(receivedCount == 1)
        #expect(firstProvider.stopCount == 1)
        #expect(secondProvider.stopCount == 1)
        #expect(firstProvider.hasObserver == false)
        #expect(secondProvider.hasObserver == false)
    }

    @Test("releases the observer when observation stops")
    func releasesObserver() {
        let provider = FakeActivityProvider(identifier: .timer)
        let registry = ActivityProviderRegistry(providers: [provider])
        weak var weakObserver: ObserverProbe?

        do {
            let observer = ObserverProbe()
            weakObserver = observer
            registry.startObserving { [observer] _ in
                observer.receive()
            }
        }

        #expect(weakObserver != nil)
        registry.stopObserving()
        #expect(weakObserver == nil)
    }

    @Test("deallocates after teardown without a provider reference cycle")
    func deallocatesRegistry() {
        let provider = FakeActivityProvider(identifier: .timer)
        weak var weakRegistry: ActivityProviderRegistry?

        do {
            let registry = ActivityProviderRegistry(providers: [provider])
            weakRegistry = registry
            registry.startObserving { _ in }
        }

        #expect(weakRegistry == nil)
        #expect(provider.hasObserver == false)
    }

    // MARK: - Per-provider enablement

    @Test("never starts a provider disabled at construction")
    func doesNotStartDisabledProvider() {
        let enabledProvider = FakeActivityProvider(identifier: .timer)
        let disabledProvider = FakeActivityProvider(identifier: .music)
        let registry = ActivityProviderRegistry(
            providers: [enabledProvider, disabledProvider],
            enabledIdentifiers: [.timer]
        )

        registry.startObserving { _ in }

        #expect(enabledProvider.startCount == 1)
        #expect(disabledProvider.startCount == 0)
        #expect(disabledProvider.hasObserver == false)
        #expect(registry.observingIdentifiers == [.timer])
    }

    @Test("stops a provider disabled while observing, leaving the others running")
    func disablingStopsOnlyThatProvider() {
        let musicProvider = FakeActivityProvider(identifier: .music)
        let timerProvider = FakeActivityProvider(identifier: .timer)
        let registry = ActivityProviderRegistry(providers: [musicProvider, timerProvider])

        registry.startObserving { _ in }
        registry.setEnabled(false, for: .music)

        #expect(musicProvider.stopCount == 1)
        #expect(musicProvider.hasObserver == false)
        #expect(timerProvider.stopCount == 0)
        #expect(timerProvider.hasObserver)
        #expect(registry.isEnabled(.music) == false)
        #expect(registry.observingIdentifiers == [.timer])
    }

    /// The acceptance criterion's second half: the observation stops *and* the
    /// activities go away. A registry that only stopped the provider would leave
    /// whatever it last emitted frozen on the island forever.
    @Test("ends the live activities of a provider that is disabled")
    func disablingEndsLiveActivities() {
        let provider = FakeActivityProvider(identifier: .recording(.screen))
        let registry = ActivityProviderRegistry(providers: [provider])
        var emissions: [ActivityEmission] = []

        registry.startObserving { emissions.append($0) }
        provider.emit(.active(StubProviderActivity(identity: ActivityIdentity("recording.screen"))))
        emissions.removeAll()

        registry.setEnabled(false, for: .screenRecording)

        #expect(emissions.count == 1)
        #expect(emissions.first?.identity == ActivityIdentity("recording.screen"))
        #expect(emissions.first?.isEnded == true)
    }

    /// Two identities from one provider is the screen-versus-audio case, and a
    /// disable that ended only the most recent one would strand the other.
    @Test("ends every live activity a provider holds")
    func disablingEndsEveryLiveActivity() {
        let provider = FakeActivityProvider(identifier: .timer)
        let registry = ActivityProviderRegistry(providers: [provider])
        var endedIdentities: Set<ActivityIdentity> = []

        registry.startObserving { emission in
            if emission.isEnded {
                endedIdentities.insert(emission.identity)
            }
        }
        provider.emit(.active(StubProviderActivity(identity: ActivityIdentity("timer.first"))))
        provider.emit(.active(StubProviderActivity(identity: ActivityIdentity("timer.second"))))

        registry.setEnabled(false, for: .timer)

        #expect(endedIdentities == [ActivityIdentity("timer.first"), ActivityIdentity("timer.second")])
    }

    @Test("does not re-end an activity the provider already ended")
    func doesNotReEndFinishedActivity() {
        let provider = FakeActivityProvider(identifier: .music)
        let registry = ActivityProviderRegistry(providers: [provider])
        var endedCount = 0

        registry.startObserving { emission in
            if emission.isEnded {
                endedCount += 1
            }
        }
        let identity = ActivityIdentity("notchflow.music")
        provider.emit(.active(StubProviderActivity(identity: identity)))
        provider.emit(.ended(identity))

        registry.setEnabled(false, for: .music)

        #expect(endedCount == 1)
    }

    /// System sources are asynchronous, so a callback can already be in flight
    /// when the switch is thrown. Forwarding it would restore the activity the
    /// disable just removed.
    @Test("drops an emission arriving after its provider is disabled")
    func dropsEmissionFromDisabledProvider() {
        let provider = FakeActivityProvider(identifier: .charging)
        let registry = ActivityProviderRegistry(providers: [provider])
        var emissions: [ActivityEmission] = []

        registry.startObserving { emissions.append($0) }
        let inFlight = provider.captureObserver()
        registry.setEnabled(false, for: .charging)
        emissions.removeAll()

        inFlight(.active(StubProviderActivity(identity: ActivityIdentity("notchflow.charging"))))

        #expect(emissions.isEmpty)
    }

    @Test("restarts a provider that is re-enabled while observing")
    func reEnablingRestartsProvider() {
        let provider = FakeActivityProvider(identifier: .music)
        let registry = ActivityProviderRegistry(providers: [provider], enabledIdentifiers: [])
        var receivedIdentities: [ActivityIdentity] = []

        registry.startObserving { receivedIdentities.append($0.identity) }
        #expect(provider.startCount == 0)

        registry.setEnabled(true, for: .music)
        provider.emit(.active(StubProviderActivity(identity: ActivityIdentity("notchflow.music"))))

        #expect(provider.startCount == 1)
        #expect(registry.observingIdentifiers == [.music])
        #expect(receivedIdentities == [ActivityIdentity("notchflow.music")])
    }

    /// Enablement is a stored preference, not a live command: a toggle thrown
    /// while nothing is observing has to survive until the next start, or the
    /// registry would resurrect a provider the user switched off.
    @Test("honours a toggle made while not observing")
    func honoursToggleMadeWhileStopped() {
        let provider = FakeActivityProvider(identifier: .audioRecording)
        let registry = ActivityProviderRegistry(providers: [provider])

        registry.setEnabled(false, for: .audioRecording)
        registry.startObserving { _ in }

        #expect(provider.startCount == 0)
        #expect(registry.observingIdentifiers.isEmpty)
    }

    @Test("ignores a toggle that does not change the setting")
    func ignoresRedundantToggle() {
        let provider = FakeActivityProvider(identifier: .timer)
        let registry = ActivityProviderRegistry(providers: [provider])

        registry.startObserving { _ in }
        registry.setEnabled(true, for: .timer)

        #expect(provider.startCount == 1)
        #expect(provider.stopCount == 0)
    }
}

extension ActivityProviderIdentifier {
    /// Spells the two recording switches the way the provider does, so a test
    /// reads `.recording(.screen)` next to the `RecordingSource` it stands for.
    fileprivate static func recording(_ source: RecordingSource) -> Self {
        switch source {
        case .screen: .screenRecording
        case .audio: .audioRecording
        }
    }
}

extension ActivityEmission {
    fileprivate var isEnded: Bool {
        if case .ended = self { return true }
        return false
    }
}

@MainActor
private final class FakeActivityProvider: ActivityProvider {
    let identifier: ActivityProviderIdentifier
    private var observer: ActivityObserver?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(identifier: ActivityProviderIdentifier) {
        self.identifier = identifier
    }

    var hasObserver: Bool {
        observer != nil
    }

    func startObserving(_ observer: @escaping ActivityObserver) {
        startCount += 1
        self.observer = observer
    }

    func stopObserving() {
        stopCount += 1
        observer = nil
    }

    func emit(_ emission: ActivityEmission) {
        observer?(emission)
    }

    /// Hands out the registry's callback so a test can fire it after the
    /// provider has been stopped — the in-flight system callback a real
    /// asynchronous source can deliver across a disable.
    func captureObserver() -> ActivityObserver {
        guard let observer else {
            fatalError("captureObserver() requires an observing provider")
        }
        return observer
    }
}

private final class ObserverProbe {
    func receive() {}
}

private struct StubProviderActivity: Activity {
    let identity: ActivityIdentity
    let kind: ActivityKind = .timer
    let priority: ActivityPriority = .normal
    let autoDismiss: AutoDismissDescriptor? = nil
}
