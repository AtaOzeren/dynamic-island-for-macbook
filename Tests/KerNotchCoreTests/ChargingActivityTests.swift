import Foundation
import Testing

@testable import KerNotchCore

/// The charging notification's value semantics. All of it is pure logic over an
/// injected state, so none of it needs a battery or an AC adapter.
@Suite("ChargingActivity")
struct ChargingActivityTests {
    private static let halfFull = BatteryLevel(fraction: 0.5)

    @Test("reports the charging kind and the normal priority for every state")
    func kindAndPriority() {
        for state in ChargingState.allCases {
            let charging = ChargingActivity(state: state, level: Self.halfFull)

            #expect(charging.kind == .charging)
            #expect(charging.priority == .normal)
        }
    }

    /// One identity across every state, because the states are readings of one
    /// fact — the machine's power situation — rather than concurrent facts. A
    /// per-state identity would let a plug-in and an unplug sit in the island
    /// side by side.
    @Test("keeps one identity across the whole state machine")
    func identityIsStableAcrossStates() {
        let identities = Set(
            ChargingState.allCases.map { ChargingActivity(state: $0, level: Self.halfFull).identity }
        )

        #expect(identities.count == 1)
    }

    /// Every state carries the descriptor, not only the terminal one: a
    /// notification that never expired would be the persistent power display
    /// the design forbids.
    @Test("auto-dismisses from every state after the documented window")
    func autoDismissesFromEveryState() {
        for state in ChargingState.allCases {
            #expect(
                ChargingActivity(state: state, level: Self.halfFull).autoDismiss
                    == AutoDismissDescriptor(after: ChargingActivity.autoDismissAfter)
            )
        }
    }

    @Test("stays on screen for four seconds")
    func autoDismissWindow() {
        #expect(ChargingActivity.autoDismissAfter == .seconds(4))
    }

    /// Charging is ambient information, not an errand: there is nowhere for a
    /// click to usefully go.
    @Test("offers no primary action")
    func noPrimaryAction() {
        #expect(ChargingActivity(state: .pluggedIn, level: Self.halfFull).primaryAction == nil)
    }

    @Test("only running on battery counts as disconnected")
    func connection() {
        #expect(ChargingState.onBattery.isConnectedToPower == false)
        #expect(ChargingState.pluggedIn.isConnectedToPower)
        #expect(ChargingState.charging.isConnectedToPower)
        #expect(ChargingState.fullyCharged.isConnectedToPower)
    }

    @Test(
        "clamps the battery level to its outline",
        arguments: [(-0.2, 0.0), (0.0, 0.0), (0.42, 0.42), (1.0, 1.0), (1.3, 1.0), (Double.nan, 0.0)]
    )
    func clampsLevel(reading: Double, expected: Double) {
        #expect(BatteryLevel(fraction: reading).fraction == expected)
    }

    @Test("compares equal only for the same state at the same level")
    func equatable() {
        #expect(
            ChargingActivity(state: .charging, level: Self.halfFull)
                == ChargingActivity(state: .charging, level: Self.halfFull)
        )
        #expect(
            ChargingActivity(state: .charging, level: Self.halfFull)
                != ChargingActivity(state: .fullyCharged, level: Self.halfFull)
        )
        #expect(
            ChargingActivity(state: .charging, level: Self.halfFull)
                != ChargingActivity(state: .charging, level: BatteryLevel(fraction: 0.6))
        )
    }
}
