import Foundation
import Testing

@testable import NotchFlowCore

/// The charging indicator's value semantics, and — more importantly — what it
/// structurally cannot say. All of it is pure logic over an injected state, so
/// none of it needs a battery or an AC adapter.
@Suite("ChargingActivity")
struct ChargingActivityTests {
    @Test("reports the charging kind and the normal priority for every state")
    func kindAndPriority() {
        for state in ChargingState.allCases {
            let charging = ChargingActivity(state: state)

            #expect(charging.kind == .charging)
            #expect(charging.priority == .normal)
        }
    }

    /// One identity across every state, because the three states are three
    /// readings of one fact — the machine's power situation — rather than three
    /// concurrent facts. A per-state identity would let `charging` and
    /// `fullyCharged` sit in the island side by side, claiming the battery is
    /// both filling and full.
    @Test("keeps one identity across the whole state machine")
    func identityIsStableAcrossStates() {
        let identities = Set(ChargingState.allCases.map { ChargingActivity(state: $0).identity })

        #expect(identities.count == 1)
    }

    /// The priority table in `docs/05-activity-model.md` marks charging
    /// auto-dismissing, and every state carries the descriptor rather than only
    /// the terminal one: a `charging` state that never expired would be the
    /// persistent power display the design forbids, just without the digits.
    @Test("auto-dismisses from every state")
    func autoDismissesFromEveryState() {
        for state in ChargingState.allCases {
            #expect(ChargingActivity(state: state).autoDismiss != nil)
        }
    }

    @Test("auto-dismisses after the documented window")
    func autoDismissWindow() {
        #expect(
            ChargingActivity(state: .charging).autoDismiss
                == AutoDismissDescriptor(after: ChargingActivity.autoDismissAfter)
        )
    }

    /// Charging is ambient information, not an errand: there is nowhere for a
    /// click to usefully go, so the activity offers no primary action rather
    /// than inventing a destination.
    @Test("offers no primary action")
    func noPrimaryAction() {
        #expect(ChargingActivity(state: .pluggedIn).primaryAction == nil)
    }

    /// The load-bearing test for this provider's one hard prohibition in
    /// `docs/06-activity-providers.md`: a persistent battery percentage is never
    /// displayed. The guarantee is structural rather than a rendering
    /// convention — the activity has no capacity member for a view to reach
    /// for, so no view can render one by accident and no later edit can
    /// reintroduce one without deleting this test.
    @Test("carries no battery capacity a view could render")
    func carriesNoCapacity() {
        let mirror = Mirror(reflecting: ChargingActivity(state: .charging))
        let storedLabels = mirror.children.compactMap(\.label)

        #expect(storedLabels == ["state"])
    }

    /// Two readings of the same state are the same value, which is what lets the
    /// provider drop the redundant re-reads the power-source callback delivers
    /// without comparing fields by hand.
    @Test("compares equal for equal states and unequal across states")
    func equatable() {
        #expect(ChargingActivity(state: .charging) == ChargingActivity(state: .charging))
        #expect(ChargingActivity(state: .charging) != ChargingActivity(state: .fullyCharged))
    }
}
