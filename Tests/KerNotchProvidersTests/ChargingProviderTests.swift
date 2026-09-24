import Foundation
import Testing

@testable import KerNotchCore
@testable import KerNotchProviders

/// The charging state machine, driven by a fake power source and a fake clock.
/// Per `docs/06-activity-providers.md`, the IOKit registration and real plug
/// transitions are the hardware half; everything asserted here — which readings
/// announce and which stay quiet — is pure logic over an injected sequence.
@Suite("ChargingProvider")
@MainActor
struct ChargingProviderTests {
    @MainActor
    private final class Fixture {
        let source = FakePowerSourceObserver()
        private(set) var emissions: [ChargingActivity] = []
        var now = Date(timeIntervalSince1970: 0)
        private(set) var provider: ChargingProvider!

        init() {
            provider = ChargingProvider(source: source, now: { [unowned self] in now })
            provider.startObserving { [unowned self] in emissions.append($0) }
        }

        var states: [ChargingState] { emissions.map(\.state) }

        func read(_ state: ChargingState, level: Double = 0.5) {
            source.emit(PowerSourceReading(state: state, level: BatteryLevel(fraction: level)))
        }

        func advance(by seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }

    /// A Mac already plugged in when KerNotch launches did not just have its
    /// cable plugged in.
    @Test("treats the first reading as a baseline, whatever it says")
    func firstReadingIsABaseline() {
        for state in ChargingState.allCases {
            let fixture = Fixture()

            fixture.read(state)

            #expect(fixture.emissions.isEmpty, "announced \(state) on launch")
        }
    }

    @Test("announces plugging in, with the battery's level")
    func announcesPlugIn() {
        let fixture = Fixture()

        fixture.read(.onBattery, level: 0.41)
        fixture.read(.charging, level: 0.41)

        #expect(fixture.emissions == [ChargingActivity(state: .charging, level: BatteryLevel(fraction: 0.41))])
    }

    @Test("announces unplugging")
    func announcesUnplug() {
        let fixture = Fixture()

        fixture.read(.fullyCharged, level: 1)
        fixture.read(.onBattery, level: 1)

        #expect(fixture.states == [.onBattery])
    }

    /// The reported defect. A charge limit pauses and resumes the charge all
    /// through the day, and each change used to reopen the island — a charging
    /// battery, then a plugged-in one, then the charging one again.
    @Test("stays quiet while a connected battery pauses and resumes its charge")
    func quietThroughChargeLimitCycles() {
        let fixture = Fixture()
        fixture.read(.onBattery)
        fixture.read(.charging)

        fixture.advance(by: 60)
        fixture.read(.pluggedIn)
        fixture.advance(by: 60)
        fixture.read(.charging)
        fixture.advance(by: 60)
        fixture.read(.fullyCharged)
        fixture.advance(by: 60)
        fixture.read(.charging)

        #expect(fixture.states == [.charging])
    }

    /// The charge usually starts a moment after the cable goes in. The
    /// notification still on screen follows it, rather than showing a
    /// connected battery without its bolt.
    @Test("refines the notification still on screen")
    func refinesWithinTheAnnouncement() {
        let fixture = Fixture()
        fixture.read(.onBattery)

        fixture.read(.pluggedIn)
        fixture.advance(by: 1)
        fixture.read(.charging)

        #expect(fixture.states == [.pluggedIn, .charging])
    }

    /// Measured from the cable, not from the last refinement, so a charge
    /// flickering in its first seconds cannot keep the notification alive.
    @Test("stops refining once the plug-in's window has passed")
    func refinementWindowRunsFromTheCable() {
        let fixture = Fixture()
        fixture.read(.onBattery)

        fixture.read(.pluggedIn)
        fixture.advance(by: 3)
        fixture.read(.charging)
        fixture.advance(by: 1)
        fixture.read(.pluggedIn)

        #expect(fixture.states == [.pluggedIn, .charging])
    }

    /// The IOKit source fires on every capacity tick while charging. A level
    /// change alone is never news.
    @Test("ignores readings that change only the level")
    func ignoresLevelTicks() {
        let fixture = Fixture()
        fixture.read(.onBattery, level: 0.40)
        fixture.read(.charging, level: 0.40)

        fixture.read(.charging, level: 0.41)
        fixture.read(.charging, level: 0.42)

        #expect(fixture.emissions.count == 1)
    }

    @Test("announces every plug-in and unplug of the day")
    func announcesEveryCableEdge() {
        let fixture = Fixture()
        fixture.read(.onBattery)

        fixture.read(.charging)
        fixture.advance(by: 600)
        fixture.read(.onBattery)
        fixture.advance(by: 600)
        fixture.read(.pluggedIn)

        #expect(fixture.states == [.charging, .onBattery, .pluggedIn])
    }

    /// Unplugging while the plug-in notification is still up replaces it; the
    /// two share one identity, so the island shows the newer fact in place.
    @Test("announces an unplug that follows the plug-in at once")
    func unplugInsideThePlugInWindow() {
        let fixture = Fixture()
        fixture.read(.onBattery)

        fixture.read(.charging)
        fixture.advance(by: 1)
        fixture.read(.onBattery)

        #expect(fixture.states == [.charging, .onBattery])
    }

    @Test("subscribes to the power source only while observing")
    func subscriptionFollowsObservation() {
        let fixture = Fixture()
        #expect(fixture.source.isObserving)

        fixture.provider.stopObserving()

        #expect(fixture.source.isObserving == false)
    }

    /// Switching the provider off and on again is not a cable edge either: the
    /// restarted provider takes a fresh baseline.
    @Test("takes a fresh baseline after being restarted")
    func restartTakesAFreshBaseline() {
        let fixture = Fixture()
        fixture.read(.onBattery)

        fixture.provider.stopObserving()
        var emissions: [ChargingActivity] = []
        fixture.provider.startObserving { emissions.append($0) }
        fixture.read(.charging)

        #expect(emissions.isEmpty)
    }
}

/// The hardware seam's test double: a power source the test drives directly,
/// standing in for the `IOPSNotificationCreateRunLoopSource` callback that can
/// only be exercised on a machine with a battery.
@MainActor
private final class FakePowerSourceObserver: PowerSourceObserving {
    private var observer: PowerSourceReadingObserver?

    var isObserving: Bool { observer != nil }

    func startObserving(_ observer: @escaping PowerSourceReadingObserver) {
        self.observer = observer
    }

    func stopObserving() {
        observer = nil
    }

    func emit(_ reading: PowerSourceReading) {
        observer?(reading)
    }
}
