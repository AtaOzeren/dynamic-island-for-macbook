import Foundation
import IOKit.ps
import Testing

@testable import NotchFlowProviders

/// The observer half of the charging indicator, with IOKit itself faked. What is
/// testable in CI is the classification of a power-source description — the
/// boundary that decides what the island says, and the boundary that drops the
/// battery percentage. Whether `IOPSNotificationCreateRunLoopSource` actually
/// fires on a real plug transition is the hardware half, per
/// `docs/11-testing-strategy.md`.
@Suite("PowerSourceDescription")
struct PowerSourceDescriptionTests {
    private static func description(
        powerSource: String,
        isCharging: Bool? = nil,
        isCharged: Bool? = nil,
        capacity: Int? = 42
    ) -> [String: Any] {
        var description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSPowerSourceStateKey: powerSource
        ]

        // Present in every fixture precisely because the classifier must never
        // consult it: a reduction that quietly grew a capacity branch would
        // still pass every other assertion here.
        if let capacity { description[kIOPSCurrentCapacityKey] = capacity }
        if let isCharging { description[kIOPSIsChargingKey] = isCharging }
        if let isCharged { description[kIOPSIsChargedKey] = isCharged }

        return description
    }

    @Test("reports battery power as no activity at all")
    func batteryPower() {
        let state = PowerSourceDescription.state(
            from: Self.description(powerSource: kIOPSBatteryPowerValue, isCharging: false)
        )

        #expect(state == .onBattery)
    }

    @Test("reports an active charge")
    func charging() {
        let state = PowerSourceDescription.state(
            from: Self.description(powerSource: kIOPSACPowerValue, isCharging: true, isCharged: false)
        )

        #expect(state == .charging)
    }

    @Test("reports a full battery")
    func fullyCharged() {
        let state = PowerSourceDescription.state(
            from: Self.description(powerSource: kIOPSACPowerValue, isCharging: false, isCharged: true)
        )

        #expect(state == .fullyCharged)
    }

    /// A machine holding at full reports charged while briefly topping up, so
    /// both flags are true at once. "Full" is the more useful of the two
    /// answers, and reporting the charge instead would flip the island back and
    /// forth for a battery that is done.
    @Test("prefers full over charging when the system reports both")
    func fullWinsOverCharging() {
        let state = PowerSourceDescription.state(
            from: Self.description(powerSource: kIOPSACPowerValue, isCharging: true, isCharged: true)
        )

        #expect(state == .fullyCharged)
    }

    /// The gap the doc's arrow diagram opens with: power is connected but the
    /// system reports neither charging nor charged — the instant after the cable
    /// goes in, and a machine plugged in but holding.
    @Test("reports connected power that is neither charging nor full")
    func pluggedInWithoutCharging() {
        let state = PowerSourceDescription.state(
            from: Self.description(powerSource: kIOPSACPowerValue, isCharging: false, isCharged: false)
        )

        #expect(state == .pluggedIn)
    }

    /// The load-bearing test for the no-percentage rule at the one boundary that
    /// can see a percentage. Two descriptions that differ only in capacity must
    /// classify identically — if the classifier ever read the capacity key, a
    /// nearly-empty and a nearly-full battery would diverge here.
    @Test("classifies identically regardless of battery capacity")
    func ignoresCapacity() {
        let states = [0, 1, 50, 99, 100].map { capacity in
            PowerSourceDescription.state(
                from: Self.description(
                    powerSource: kIOPSACPowerValue,
                    isCharging: true,
                    capacity: capacity
                )
            )
        }

        #expect(Set(states) == [.charging])
    }

    /// A description missing the keys entirely — a power source type IOKit knows
    /// about but this reduction does not — falls back to the state with no
    /// activity, rather than guessing a charge that may not be happening.
    @Test("treats an unreadable description as being on battery")
    func missingKeys() {
        #expect(PowerSourceDescription.state(from: [:]) == .onBattery)
    }
}
