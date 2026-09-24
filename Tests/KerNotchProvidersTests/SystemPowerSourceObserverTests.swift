import Foundation
import IOKit.ps
import Testing

@testable import KerNotchCore
@testable import KerNotchProviders

/// The observer half of the charging indicator, with IOKit itself faked. What is
/// testable in CI is the classification of a power-source description — the
/// boundary that decides what the island says. Whether
/// `IOPSNotificationCreateRunLoopSource` actually fires on a real plug
/// transition is the hardware half, per `docs/11-testing-strategy.md`.
@Suite("PowerSourceDescription")
struct PowerSourceDescriptionTests {
    private static func description(
        powerSource: String,
        isCharging: Bool? = nil,
        isCharged: Bool? = nil,
        capacity: Int? = 42,
        maximumCapacity: Int? = 100
    ) -> [String: Any] {
        var description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSPowerSourceStateKey: powerSource,
        ]

        if let capacity { description[kIOPSCurrentCapacityKey] = capacity }
        if let maximumCapacity { description[kIOPSMaxCapacityKey] = maximumCapacity }
        if let isCharging { description[kIOPSIsChargingKey] = isCharging }
        if let isCharged { description[kIOPSIsChargedKey] = isCharged }

        return description
    }

    private static func state(_ description: [String: Any]) -> ChargingState? {
        PowerSourceDescription.reading(from: description)?.state
    }

    @Test("reports battery power")
    func batteryPower() {
        #expect(Self.state(Self.description(powerSource: kIOPSBatteryPowerValue, isCharging: false)) == .onBattery)
    }

    @Test("reports an active charge")
    func charging() {
        #expect(
            Self.state(Self.description(powerSource: kIOPSACPowerValue, isCharging: true, isCharged: false))
                == .charging
        )
    }

    @Test("reports a full battery")
    func fullyCharged() {
        #expect(
            Self.state(Self.description(powerSource: kIOPSACPowerValue, isCharging: false, isCharged: true))
                == .fullyCharged
        )
    }

    /// A machine holding at full reports charged while briefly topping up, so
    /// both flags are true at once. "Full" is the more useful of the two answers.
    @Test("prefers full over charging when the system reports both")
    func fullWinsOverCharging() {
        #expect(
            Self.state(Self.description(powerSource: kIOPSACPowerValue, isCharging: true, isCharged: true))
                == .fullyCharged
        )
    }

    /// The instant after the cable goes in, and a machine holding at its charge
    /// limit: power is connected, but the system reports neither charging nor
    /// charged.
    @Test("reports connected power that is neither charging nor full")
    func pluggedInWithoutCharging() {
        #expect(
            Self.state(Self.description(powerSource: kIOPSACPowerValue, isCharging: false, isCharged: false))
                == .pluggedIn
        )
    }

    @Test("reads the level against the reported maximum")
    func readsLevel() throws {
        let reading = try #require(
            PowerSourceDescription.reading(
                from: Self.description(powerSource: kIOPSACPowerValue, capacity: 85, maximumCapacity: 100)
            )
        )

        #expect(reading.level == BatteryLevel(fraction: 0.85))
    }

    /// A reading with no charge to draw is no reading, rather than a battery
    /// drawn empty or full on a guess.
    @Test(
        "gives no reading without a usable capacity",
        arguments: [(nil, 100), (42, nil), (42, 0)] as [(Int?, Int?)]
    )
    func noReadingWithoutCapacity(capacity: Int?, maximum: Int?) {
        let description = Self.description(
            powerSource: kIOPSACPowerValue,
            isCharging: true,
            capacity: capacity,
            maximumCapacity: maximum
        )

        #expect(PowerSourceDescription.reading(from: description) == nil)
    }

    /// A description missing the power-source key — a type IOKit knows about
    /// but this reduction does not — reads as disconnected rather than guessing a
    /// charge that may not be happening.
    @Test("treats a missing power source as being on battery")
    func missingPowerSource() {
        let description: [String: Any] = [kIOPSCurrentCapacityKey: 50, kIOPSMaxCapacityKey: 100]

        #expect(Self.state(description) == .onBattery)
    }
}
