import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

/// What the charging views draw, and — the point of this suite — what they
/// structurally cannot draw. `docs/06-activity-providers.md` forbids a
/// persistent battery percentage, and the acceptance criterion for todo 48 asks
/// for that to be assertable rather than merely observed in a screenshot.
@Suite("ChargingActivityView")
struct ChargingActivityViewTests {
    @Test("gives each state its own glyph")
    func glyphPerState() {
        let symbols = ChargingState.allCases.map {
            ChargingPresentation(activity: ChargingActivity(state: $0)).symbolName
        }

        #expect(Set(symbols).count == ChargingState.allCases.count)
    }

    @Test("states a completed transition rather than a reading")
    func titles() {
        #expect(ChargingPresentation(activity: ChargingActivity(state: .pluggedIn)).title == "Plugged In")
        #expect(ChargingPresentation(activity: ChargingActivity(state: .charging)).title == "Charging")
        #expect(ChargingPresentation(activity: ChargingActivity(state: .fullyCharged)).title == "Fully Charged")
    }

    /// The load-bearing test for todo 48's second acceptance criterion. Every
    /// string any charging view can put on screen, checked for digits: a
    /// percentage cannot be rendered without one, so a run with no digits
    /// anywhere is a run with no percentage anywhere.
    @Test("renders no digit in any string, in any state")
    func rendersNoDigits() {
        for state in ChargingState.allCases {
            let presentation = ChargingPresentation(activity: ChargingActivity(state: state))
            let rendered = [presentation.title, presentation.accessibilityLabel]

            for string in rendered {
                #expect(string.contains(where: \.isNumber) == false)
            }
        }
    }

    /// The percentage is kept out at the type level too, not only by the strings
    /// happening to omit it: the presentation carries a state and nothing else,
    /// so there is no numeric member for a future view to reach for.
    @Test("exposes no numeric member a future view could render")
    func exposesNoNumber() {
        let mirror = Mirror(reflecting: ChargingPresentation(activity: ChargingActivity(state: .charging)))

        #expect(mirror.children.compactMap(\.label) == ["state"])
    }

    /// The compact pill distinguishes a finished charge from a running one
    /// without expanding, which is the whole reason the slot overrides the
    /// kind's shared bolt.
    @Test("varies the compact glyph by state")
    func compactSlotGlyphVariesByState() {
        let charging = chargingCompactSlot(for: ChargingActivity(state: .charging))
        let full = chargingCompactSlot(for: ChargingActivity(state: .fullyCharged))

        #expect(charging.symbolName != full.symbolName)
        #expect(charging.accessibilityLabel == "Charging")
        #expect(full.accessibilityLabel == "Fully Charged")
    }

    /// The three states share one identity, so the pill replaces the slot in
    /// place rather than accumulating one per state.
    @Test("keeps one compact slot identity across states")
    func compactSlotIdentityIsStable() {
        let identifiers = ChargingState.allCases.map {
            chargingCompactSlot(for: ChargingActivity(state: $0)).id
        }

        #expect(Set(identifiers).count == 1)
    }

    /// The compact slot draws a glyph alone — the label field is what would
    /// carry a "82%" caption beside it, and it stays empty.
    @Test("draws no caption beside the compact glyph")
    func compactSlotHasNoLabel() {
        #expect(chargingCompactSlot(for: ChargingActivity(state: .charging)).label == nil)
    }

    /// An activity routed through the generic kind-based path — the one the
    /// expanded list uses — still says something true and still says no number.
    @Test("routes through the generic row without inventing a number")
    func genericRow() {
        let rows = expandedRows(for: [ChargingActivity(state: .charging)])

        #expect(rows.count == 1)
        #expect(rows[0].title.contains(where: \.isNumber) == false)
    }
}
