import Foundation
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

/// What the charging views draw. The level is shown as the width of the
/// battery's fill and never as digits on screen, per
/// `docs/06-activity-providers.md`.
@Suite("ChargingActivityView")
struct ChargingActivityViewTests {
    private static func presentation(_ state: ChargingState, level: Double = 0.5) -> ChargingPresentation {
        ChargingPresentation(activity: ChargingActivity(state: state, level: BatteryLevel(fraction: level)))
    }

    @Test("states a completed transition rather than a reading")
    func titles() {
        #expect(Self.presentation(.onBattery).title == "Unplugged")
        #expect(Self.presentation(.pluggedIn).title == "Plugged In")
        #expect(Self.presentation(.charging).title == "Charging")
        #expect(Self.presentation(.fullyCharged).title == "Fully Charged")
    }

    @Test("writes no digit on screen, in any state, at any level")
    func titleHasNoDigits() {
        for state in ChargingState.allCases {
            for level in [0.0, 0.07, 0.5, 0.99, 1.0] {
                #expect(Self.presentation(state, level: level).title.contains(where: \.isNumber) == false)
            }
        }
    }

    /// VoiceOver cannot see the fill, so it is told the level instead.
    @Test("tells VoiceOver the level the fill shows")
    func accessibilityLabelCarriesTheLevel() {
        let label = Self.presentation(.charging, level: 0.85).accessibilityLabel

        #expect(label.hasPrefix("Charging"))
        #expect(label.contains("85"))
    }

    @Test("draws the bolt only while the battery is filling")
    func boltOnlyWhileCharging() {
        #expect(Self.presentation(.charging).showsChargingBolt)
        #expect(Self.presentation(.pluggedIn).showsChargingBolt == false)
        #expect(Self.presentation(.fullyCharged).showsChargingBolt == false)
        #expect(Self.presentation(.onBattery).showsChargingBolt == false)
    }

    @Test("fills green while connected, whatever the level")
    func connectedFillIsGreen() {
        for state in ChargingState.allCases where state.isConnectedToPower {
            #expect(Self.presentation(state, level: 0.05).fillTone == .connected)
        }
    }

    @Test(
        "fills an unplugged battery red at or below twenty percent",
        arguments: [(0.0, BatteryFillTone.low), (0.2, .low), (0.21, .standard), (1.0, .standard)]
    )
    func unpluggedFillTone(level: Double, expected: BatteryFillTone) {
        #expect(Self.presentation(.onBattery, level: level).fillTone == expected)
    }

    @Test("carries the battery into the compact slot")
    func compactSlotCarriesThePresentation() {
        let activity = ChargingActivity(state: .charging, level: BatteryLevel(fraction: 0.41))
        let slot = chargingCompactSlot(for: activity)

        #expect(slot.charging == ChargingPresentation(activity: activity))
        #expect(slot.accessibilityLabel == ChargingPresentation(activity: activity).accessibilityLabel)
    }

    /// The states share one identity, so the pill replaces the slot in place
    /// rather than accumulating one per state.
    @Test("keeps one compact slot identity across states")
    func compactSlotIdentityIsStable() {
        let identifiers = ChargingState.allCases.map {
            chargingCompactSlot(for: ChargingActivity(state: $0, level: BatteryLevel(fraction: 0.5))).id
        }

        #expect(Set(identifiers).count == 1)
    }

    /// An activity routed through the generic kind-based path still says
    /// something true and still says no number.
    @Test("routes through the generic row without inventing a number")
    func genericRow() {
        let rows = expandedRows(for: [ChargingActivity(state: .charging, level: BatteryLevel(fraction: 0.5))])

        #expect(rows.count == 1)
        #expect(rows[0].title.contains(where: \.isNumber) == false)
    }
}
