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

    // MARK: - One surface, hairline separated

    /// The panel is one sheet with rows, not a stack of floating cards. The
    /// separator sits inside the gap the size model already reserves, so
    /// changing the treatment must not change the panel's height.
    @Test("the separator occupies the gap the height model already reserves")
    func separatorFitsTheReservedGap() {
        let metrics = ExpandedPanelMetrics()
        let one = expandedPanelSize(rowCount: 1, metrics: metrics)
        let three = expandedPanelSize(rowCount: 3, metrics: metrics)

        #expect(
            three.height - one.height
                == (metrics.rowHeight + metrics.rowSpacing) * 2
        )
        #expect(metrics.rowSpacing >= 1, "a hairline needs a gap to sit in")
    }

    /// `rowSpacing` used to double as the horizontal gap inside a row, so
    /// giving the divider room squeezed every glyph against its label. The two
    /// are separate budgets now and must stay that way.
    @Test("vertical and horizontal spacing are independent budgets")
    func spacingBudgetsAreIndependent() {
        let widened = ExpandedPanelMetrics(rowSpacing: 40)

        #expect(widened.columnSpacing == ExpandedPanelMetrics().columnSpacing)
        #expect(widened.rowSpacing != widened.columnSpacing)
    }

    // MARK: - Growing with a disclosed group

    /// Opening a group's sessions makes the panel taller.
    ///
    /// The island's surface is sized from this same function, so a disclosure it
    /// did not account for was a disclosure drawn past the bottom of the island
    /// and onto the desktop.
    @Test("the panel grows when a group is disclosed")
    func panelGrowsWithDisclosure() {
        let sessions = [
            Self.agent(.claudeCode, state: .usingTool),
            Self.agent(.claudeCode, state: .working),
            Self.agent(.claudeCode, state: .thinking),
        ]

        let collapsed = expandedPanelSize(for: sessions)
        let disclosed = expandedPanelSize(for: sessions, disclosedAgentIDs: [.claudeCode])

        #expect(disclosed.height > collapsed.height)
        #expect(
            disclosed.height - collapsed.height
                == aiAgentGroupDisclosureHeight(sessionCount: sessions.count, isDisclosed: true)
        )
    }

    /// Every extra session adds a row, so the panel keeps up as an agent opens
    /// more of them.
    @Test("each disclosed session adds its own row height")
    func eachDisclosedSessionAddsARow() {
        func height(sessionCount: Int) -> CGFloat {
            let sessions = (0..<sessionCount).map { _ in
                Self.agent(.claudeCode, state: .usingTool)
            }
            return expandedPanelSize(for: sessions, disclosedAgentIDs: [.claudeCode]).height
        }

        let two = height(sessionCount: 2)
        let three = height(sessionCount: 3)
        let four = height(sessionCount: 4)

        #expect(three - two == four - three)
        #expect(three > two)
    }

    /// Disclosing one agent must not resize another's row.
    @Test("disclosure only grows the agent that was opened")
    func disclosureIsPerAgent() {
        let activities: [any Activity] = [
            Self.agent(.claudeCode, state: .usingTool),
            Self.agent(.claudeCode, state: .working),
            Self.agent(.opencode, state: .usingTool),
            Self.agent(.opencode, state: .working),
        ]

        let none = expandedPanelSize(for: activities)
        let claudeOnly = expandedPanelSize(for: activities, disclosedAgentIDs: [.claudeCode])
        let both = expandedPanelSize(
            for: activities,
            disclosedAgentIDs: [.claudeCode, .opencode]
        )

        #expect(claudeOnly.height > none.height)
        #expect(both.height - claudeOnly.height == claudeOnly.height - none.height)
    }

    private static func agent(_ id: IPCAgentID, state: AIAgentState) -> AIAgentActivity {
        AIAgentActivity(agent: id, sessionID: UUID(), state: state, detail: "Working")
    }

    // MARK: - Scrolling past the ceiling

    /// The panel grows to fit and only scrolls once it cannot.
    @Test("the panel grows before it scrolls")
    func panelGrowsBeforeScrolling() {
        let panelMetrics = PanelMetrics.default
        let metrics = ExpandedItemMetrics.default
        let step = metrics.panel.rowHeight + metrics.panel.rowSpacing

        var rows = 1
        while rows < 200,
            !expandedPanelOverflowsWindow(
                for: Self.rows(rows),
                metrics: metrics,
                panelMetrics: panelMetrics
            )
        {
            rows += 1
        }

        // Whatever the ceiling is, several rows fit under it before scrolling
        // starts — 260pt used to allow barely a handful.
        #expect(rows > 6, "the island scrolls after only \(rows - 1) rows")
        #expect(CGFloat(rows) * step > panelMetrics.maximumExpandedSize.height * 0.7)
    }

    /// Past the ceiling the panel stops growing, and the content it has to show
    /// is genuinely taller than the box — which is the only thing that makes a
    /// scroll view scroll.
    @Test("an overflowing list is taller than the box that shows it")
    func overflowingContentExceedsItsViewport() {
        let panelMetrics = PanelMetrics.default
        let metrics = ExpandedItemMetrics.default
        let many = Self.rows(40)

        let box = expandedPanelSize(for: many, metrics: metrics, panelMetrics: panelMetrics)
        let natural =
            CGFloat(many.count) * metrics.panel.rowHeight
            + CGFloat(many.count - 1) * metrics.panel.rowSpacing
            + metrics.panel.contentInset * 2

        #expect(expandedPanelOverflowsWindow(for: many, metrics: metrics, panelMetrics: panelMetrics))
        #expect(box.height == panelMetrics.maximumExpandedSize.height)
        #expect(natural > box.height, "nothing to scroll: content fits its own viewport")
    }

    /// The clamped height belongs to the scroll container, not to the content.
    /// Putting it on the content is what made an overflowing list clip at both
    /// ends instead of scrolling, and only the view can show that.
    @Test("the height is applied to the scroll container")
    func heightIsAppliedToTheScrollContainer() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/NotchFlowUI/ExpandedActivityView.swift"),
            encoding: .utf8
        )

        #expect(source.contains(".frame(width: size.width, alignment: .top)"))
        #expect(source.contains("ScrollWhenTaller(isEnabled: scrolls, height: size.height)"))
        #expect(source.contains("ScrollView(.vertical) { content }\n                .frame(height: height)"))
        // The old shape: content forced to the clamped height before wrapping.
        #expect(!source.contains(".frame(width: size.width, height: size.height, alignment: .top)"))
    }

    private static func rows(_ count: Int) -> [any Activity] {
        (0..<count).map { index in
            StubActivity(
                identity: ActivityIdentity("scroll.\(index)"),
                kind: .fileTransfer,
                priority: .normal
            ) as any Activity
        }
    }
}
