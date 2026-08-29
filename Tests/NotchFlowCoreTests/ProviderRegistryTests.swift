import Testing
@testable import NotchFlowCore

@Suite("ProviderRegistry")
struct ProviderRegistryTests {
    @Test("starts every registered provider")
    func startsRegisteredProviders() {
        let firstProvider = FakeActivityProvider()
        let secondProvider = FakeActivityProvider()
        let registry = ActivityProviderRegistry(providers: [firstProvider, secondProvider])

        registry.startObserving { _ in }

        #expect(firstProvider.startCount == 1)
        #expect(secondProvider.startCount == 1)
    }

    @Test("forwards emitted activities while observing")
    func forwardsActivities() {
        let provider = FakeActivityProvider()
        let registry = ActivityProviderRegistry(providers: [provider])
        var receivedIdentities: [ActivityIdentity] = []

        registry.startObserving { activity in
            receivedIdentities.append(activity.identity)
        }
        provider.emit(StubProviderActivity(identity: ActivityIdentity("timer.focus")))

        #expect(receivedIdentities == [ActivityIdentity("timer.focus")])
    }

    @Test("stops every provider and suppresses later emissions")
    func stopsProvidersAndEmissions() {
        let firstProvider = FakeActivityProvider()
        let secondProvider = FakeActivityProvider()
        let registry = ActivityProviderRegistry(providers: [firstProvider, secondProvider])
        var receivedCount = 0

        registry.startObserving { _ in
            receivedCount += 1
        }
        firstProvider.emit(StubProviderActivity(identity: ActivityIdentity("timer.before-stop")))

        registry.stopObserving()
        firstProvider.emit(StubProviderActivity(identity: ActivityIdentity("timer.after-stop")))
        secondProvider.emit(StubProviderActivity(identity: ActivityIdentity("music.after-stop")))

        #expect(receivedCount == 1)
        #expect(firstProvider.stopCount == 1)
        #expect(secondProvider.stopCount == 1)
        #expect(firstProvider.hasObserver == false)
        #expect(secondProvider.hasObserver == false)
    }

    @Test("releases the observer when observation stops")
    func releasesObserver() {
        let provider = FakeActivityProvider()
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
        let provider = FakeActivityProvider()
        weak var weakRegistry: ActivityProviderRegistry?

        do {
            let registry = ActivityProviderRegistry(providers: [provider])
            weakRegistry = registry
            registry.startObserving { _ in }
        }

        #expect(weakRegistry == nil)
        #expect(provider.hasObserver == false)
    }
}

private final class FakeActivityProvider: ActivityProvider {
    private var observer: ActivityObserver?

    private(set) var startCount = 0
    private(set) var stopCount = 0

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

    func emit(_ activity: any Activity) {
        observer?(activity)
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
