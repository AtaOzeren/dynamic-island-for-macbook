import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

@Suite("ExpandedActivityView")
@MainActor
struct ExpandedActivityViewTests {
    private struct StubActivity: Activity {
        let identity: ActivityIdentity
        let kind: ActivityKind
        let priority: ActivityPriority
        var primaryAction: PrimaryAction?
    }

    private static func activity(
        _ name: String,
        _ kind: ActivityKind,
        _ priority: ActivityPriority,
        primaryAction: PrimaryAction? = nil
    ) -> StubActivity {
        StubActivity(
            identity: ActivityIdentity(name),
            kind: kind,
            priority: priority,
            primaryAction: primaryAction
        )
    }

    /// The worked example in `docs/05-activity-model.md`: music, a timer, and a
    /// file transfer active at once, ordered by priority then registration time.
    private static func workedExample() -> ActivityManager {
        let manager = ActivityManager()
        manager.register(activity("music", .music, .low), at: Date(timeIntervalSince1970: 1))
        manager.register(activity("timer", .timer, .high), at: Date(timeIntervalSince1970: 2))
        manager.register(activity("transfer", .fileTransfer, .normal), at: Date(timeIntervalSince1970: 3))
        return manager
    }

    @Test("renders one row per activity in the manager's priority order")
    func rowsFollowManagerOrder() {
        let rows = expandedRows(for: Self.workedExample().expandedActivities)

        #expect(rows.map(\.id) == ["timer", "transfer", "music"])
    }

    @Test("orders rows identically to the compact pill")
    func rowsMatchCompactOrdering() {
        let manager = Self.workedExample()

        let rowIDs = expandedRows(for: manager.expandedActivities).map(\.id)
        let slotIDs = compactSlots(for: manager.compactPresentation)
            .filter { $0.overflowCount == nil }
            .map(\.id)

        #expect(Array(rowIDs.prefix(slotIDs.count)) == slotIDs)
    }

    /// The expanded view never truncates: where the compact pill collapses the
    /// tail into `+2`, the expanded list still shows all four activities.
    @Test("lists every activity past the compact capacity without an overflow row")
    func expandedListNeverTruncates() {
        let manager = Self.workedExample()
        manager.register(
            Self.activity("recording", .recording, .high),
            at: Date(timeIntervalSince1970: 4)
        )

        let rows = expandedRows(for: manager.expandedActivities)
        let compact = manager.compactPresentation

        #expect(compact.overflowCount == 2)
        #expect(rows.count == 4)
        #expect(Set(rows.map(\.id)) == ["timer", "recording", "transfer", "music"])
    }

    @Test("carries the primary action affordance only for activities that offer one")
    func primaryActionIsCarriedPerActivity() {
        let manager = ActivityManager()
        manager.register(
            Self.activity(
                "music",
                .music,
                .low,
                primaryAction: PrimaryAction(title: "Open Spotify")
            ),
            at: Date(timeIntervalSince1970: 1)
        )
        manager.register(
            Self.activity("transfer", .fileTransfer, .normal),
            at: Date(timeIntervalSince1970: 2)
        )

        let rows = expandedRows(for: manager.expandedActivities)

        #expect(rows.first(where: { $0.id == "transfer" })?.primaryAction == nil)
        #expect(rows.first(where: { $0.id == "music" })?.primaryAction?.title == "Open Spotify")
    }

    @Test("grows the panel by one row height per activity")
    func panelGrowsWithRowCount() {
        let metrics = ExpandedPanelMetrics.default
        let one = expandedPanelSize(rowCount: 1, metrics: metrics)
        let two = expandedPanelSize(rowCount: 2, metrics: metrics)

        #expect(two.height - one.height == metrics.rowHeight + metrics.rowSpacing)
        #expect(one.width == metrics.width)
    }

    @Test("draws nothing when there is no activity")
    func emptySetHasNoPanel() {
        #expect(expandedPanelSize(rowCount: 0) == .zero)
        #expect(expandedRows(for: ActivityManager().expandedActivities).isEmpty)
    }

    /// The panel frame is allocated once at its maximum and never resized, so a
    /// long list has to stay inside it and scroll rather than draw past the edge.
    @Test("clamps to the allocated window and reports that it must scroll")
    func longListClampsToTheWindow() {
        let panelMetrics = PanelMetrics.default
        let rowCount = 40

        let size = expandedPanelSize(rowCount: rowCount, panelMetrics: panelMetrics)

        #expect(size.height == panelMetrics.maximumExpandedSize.height)
        #expect(expandedPanelOverflowsWindow(rowCount: rowCount, panelMetrics: panelMetrics))
        #expect(expandedPanelOverflowsWindow(rowCount: 3, panelMetrics: panelMetrics) == false)
    }
}
