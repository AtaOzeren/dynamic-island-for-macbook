import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowProviders

/// The charging state machine, driven by a fake power source. Per
/// `docs/06-activity-providers.md`, the IOKit registration and real plug
/// transitions are the hardware half; everything asserted here — the mapping
/// from power state to activity, the suppression of redundant re-reads, and
/// teardown on unplug — is pure logic over an injected sequence.
@Suite("ChargingProvider")
@MainActor
struct ChargingProviderTests {
    private struct Fixture {
        let provider: ChargingProvider
        let source: FakePowerSourceObserver
        let emissions: Emissions
    }

    /// Records every emission in order, including the `nil`s: teardown is an
    /// emission the manager must actually receive, so dropping the `nil`s would
    /// hide the exact bug these tests exist to catch.
    private final class Emissions {
        private(set) var values: [ChargingActivity?] = []

        var states: [ChargingState?] { values.map { $0?.state } }
        var count: Int { values.count }

        func record(_ activity: ChargingActivity?) {
            values.append(activity)
        }
    }

    private static func makeProvider() -> Fixture {
        let source = FakePowerSourceObserver()
        let emissions = Emissions()
        let provider = ChargingProvider(source: source)
        provider.startObserving { emissions.record($0) }
        return Fixture(provider: provider, source: source, emissions: emissions)
    }

    @Test("produces no activity while the machine runs on battery")
    func idleOnBattery() {
        let fixture = Self.makeProvider()

        fixture.source.emit(.onBattery)

        #expect(fixture.provider.currentActivity == nil)
        #expect(fixture.emissions.count == 0)
    }

    /// The whole documented happy path in one pass: connecting power registers
    /// the activity, the charge starting updates it, and reaching full updates
    /// it again — one element throughout, because the states share an identity.
    @Test("walks plugged in to charging to fully charged")
    func happyPath() {
        let fixture = Self.makeProvider()

        fixture.source.emit(.pluggedIn)
        fixture.source.emit(.charging)
        fixture.source.emit(.fullyCharged)

        #expect(fixture.emissions.states == [.pluggedIn, .charging, .fullyCharged])
        #expect(fixture.provider.currentActivity == ChargingActivity(state: .fullyCharged))
    }

    /// The load-bearing test for this provider's power behaviour, and for the
    /// no-persistent-display rule in second-order form.
    ///
    /// The IOKit source fires on *every* power-source change, which includes
    /// each capacity tick while charging. Since `ActivityManager` restarts the
    /// auto-dismiss window on every `update()`, a provider that re-emitted on
    /// each callback would hold the island open for the entire charge — a
    /// persistent power display in all but digits. Dedupe is what makes the
    /// documented auto-dismiss actually reachable.
    @Test("ignores repeated callbacks that carry no state change")
    func suppressesRedundantCallbacks() {
        let fixture = Self.makeProvider()

        fixture.source.emit(.charging)
        fixture.source.emit(.charging)
        fixture.source.emit(.charging)

        #expect(fixture.emissions.count == 1)
    }

    /// Unplugging is teardown, not a fourth state: the activity disappears at
    /// once rather than lingering for its dismiss window, because the fact it
    /// reported has stopped being true.
    @Test("tears down when power is disconnected")
    func teardownOnUnplug() {
        let fixture = Self.makeProvider()

        fixture.source.emit(.charging)
        fixture.source.emit(.onBattery)

        #expect(fixture.emissions.states == [.charging, nil])
        #expect(fixture.provider.currentActivity == nil)
    }

    /// A machine that is already on battery when NotchFlow launches must not
    /// produce a teardown for an activity that was never registered.
    @Test("does not emit a teardown for a state it never registered")
    func noRedundantTeardown() {
        let fixture = Self.makeProvider()

        fixture.source.emit(.onBattery)
        fixture.source.emit(.onBattery)

        #expect(fixture.emissions.count == 0)
    }

    /// Batteries drain below full while still plugged in and resume charging.
    /// The doc's arrow diagram is the happy path, not a permitted-transition
    /// table, so the provider reports what the system says rather than refusing
    /// a state it considers backwards.
    @Test("reports a resumed charge after reaching full")
    func resumesChargingAfterFull() {
        let fixture = Self.makeProvider()

        fixture.source.emit(.fullyCharged)
        fixture.source.emit(.charging)

        #expect(fixture.emissions.states == [.fullyCharged, .charging])
    }

    /// Re-plugging after an unplug is a new notification, not a continuation:
    /// the dedupe must have been cleared by the teardown, or the second charge
    /// of the day would never appear.
    @Test("registers again after a teardown")
    func registersAgainAfterTeardown() {
        let fixture = Self.makeProvider()

        fixture.source.emit(.charging)
        fixture.source.emit(.onBattery)
        fixture.source.emit(.charging)

        #expect(fixture.emissions.states == [.charging, nil, .charging])
    }

    @Test("subscribes to the power source only while observing")
    func subscriptionFollowsObservation() {
        let fixture = Self.makeProvider()
        #expect(fixture.source.isObserving)

        fixture.provider.stopObserving()

        #expect(fixture.source.isObserving == false)
    }

    /// Teardown must also clear the remembered state, so a provider restarted
    /// into the same power state still reports it rather than deduping against
    /// a reading from its previous life.
    @Test("re-reports the current state after being restarted")
    func restartReportsCurrentState() {
        let fixture = Self.makeProvider()
        fixture.source.emit(.charging)

        fixture.provider.stopObserving()

        let emissions = Emissions()
        fixture.provider.startObserving { emissions.record($0) }
        fixture.source.emit(.charging)

        #expect(emissions.states == [.charging])
    }

    /// Nothing in this provider counts, so nothing in it may schedule a wakeup:
    /// every emission is an edge from the IOKit callback, per the update-cadence
    /// rule in `docs/06-activity-providers.md`.
    @Test("emits only in response to a power source callback")
    func emitsOnlyOnCallbacks() {
        let fixture = Self.makeProvider()

        #expect(fixture.emissions.count == 0)

        fixture.source.emit(.pluggedIn)

        #expect(fixture.emissions.count == 1)
    }
}

/// The hardware seam's test double: a power source the test drives directly,
/// standing in for the `IOPSNotificationCreateRunLoopSource` callback that can
/// only be exercised on a machine with a battery.
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
