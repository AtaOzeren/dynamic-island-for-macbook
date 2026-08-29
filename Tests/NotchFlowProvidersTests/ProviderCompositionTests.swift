import Foundation
import Testing
@testable import NotchFlowCore
@testable import NotchFlowProviders

/// The acceptance criterion end to end: a provider switched off in settings
/// stops observing *and* its activities leave the island. Asserting against the
/// manager rather than against emissions is what makes the second half real —
/// an end that never reaches the manager is an activity still on screen.
@Suite("ProviderComposition")
@MainActor
struct ProviderCompositionTests {
    private struct Fixture {
        let manager: ActivityManager
        let registry: ActivityProviderRegistry
        let power: FakePowerSourceObserver
        let sessions: FakeRecordingObserver
    }

    private static func makeFixture(
        enabled: Set<ActivityProviderIdentifier> = Set(ActivityProviderIdentifier.allCases)
    ) -> Fixture {
        let power = FakePowerSourceObserver()
        let sessions = FakeRecordingObserver()
        // A dismiss window that never elapses. The charging activity carries a
        // real auto-dismiss, and letting it fire would make these tests race
        // the manager over which of the two removed the activity.
        let manager = ActivityManager(sleep: { _ in try? await Task.sleep(for: .seconds(3600)) })
        let registry = ActivityProviderRegistry(
            providers: [
                ActivityProviderRegistration.charging(ChargingProvider(source: power)),
                ActivityProviderRegistration.recording(
                    RecordingProvider(
                        source: .screen,
                        sessions: sessions,
                        scheduler: FakeTickScheduler(),
                        now: { Date(timeIntervalSince1970: 0) }
                    )
                )
            ],
            enabledIdentifiers: enabled
        )

        registry.startObserving(into: manager)
        return Fixture(manager: manager, registry: registry, power: power, sessions: sessions)
    }

    @Test("routes an emitted activity into the manager")
    func routesActivityIntoManager() {
        let fixture = Self.makeFixture()

        fixture.power.emit(.charging)

        #expect(fixture.manager.activeActivities.map(\.identity) == [ActivityIdentity("notchflow.charging")])
    }

    @Test("removes the activities of a provider disabled in settings")
    func disablingRemovesActivities() {
        let fixture = Self.makeFixture()
        fixture.power.emit(.charging)
        fixture.sessions.emit(RecordingSession(startedAt: Date(timeIntervalSince1970: 0)))

        fixture.registry.setEnabled(false, for: .charging)

        #expect(fixture.power.isObserving == false)
        #expect(fixture.manager.activeActivities.map(\.identity) == [
            RecordingActivity.identity(for: .screen)
        ])
    }

    @Test("never observes a provider disabled before the registry starts")
    func disabledProviderNeverObserves() {
        let fixture = Self.makeFixture(enabled: [.screenRecording])

        #expect(fixture.power.isObserving == false)
        #expect(fixture.sessions.isObserving)
    }

    @Test("observes again when a provider is re-enabled")
    func reEnablingResumesObservation() {
        let fixture = Self.makeFixture()
        fixture.registry.setEnabled(false, for: .charging)

        fixture.registry.setEnabled(true, for: .charging)
        fixture.power.emit(.charging)

        #expect(fixture.power.isObserving)
        #expect(fixture.manager.activeActivities.map(\.identity) == [ActivityIdentity("notchflow.charging")])
    }

    /// The registry holds the manager weakly, so a composition root torn down
    /// while providers are live must not keep the manager — and with it the
    /// whole presentation layer — alive through a callback nobody reads.
    @Test("does not retain the manager it routes into")
    func doesNotRetainManager() {
        let power = FakePowerSourceObserver()
        let registry = ActivityProviderRegistry(
            providers: [ActivityProviderRegistration.charging(ChargingProvider(source: power))]
        )
        weak var weakManager: ActivityManager?

        do {
            let manager = ActivityManager()
            weakManager = manager
            registry.startObserving(into: manager)
        }

        #expect(weakManager == nil)
    }
}

@MainActor
private final class FakePowerSourceObserver: PowerSourceObserving {
    private var observer: PowerSourceStateObserver?

    var isObserving: Bool { observer != nil }

    func startObserving(_ observer: @escaping PowerSourceStateObserver) {
        self.observer = observer
    }

    func stopObserving() {
        observer = nil
    }

    func emit(_ state: PowerSourceState) {
        observer?(state)
    }
}

@MainActor
private final class FakeRecordingObserver: RecordingObserving {
    private var observer: RecordingSessionObserver?

    var isObserving: Bool { observer != nil }

    func startObserving(_ observer: @escaping RecordingSessionObserver) {
        self.observer = observer
    }

    func stopObserving() {
        observer = nil
    }

    func emit(_ session: RecordingSession?) {
        observer?(session)
    }
}

@MainActor
private final class FakeTickScheduler: TickScheduling {
    private var tick: (@MainActor () -> Void)?

    var isScheduled: Bool { tick != nil }

    func schedule(_ tick: @escaping @MainActor () -> Void) {
        self.tick = tick
    }

    func cancel() {
        tick = nil
    }
}
