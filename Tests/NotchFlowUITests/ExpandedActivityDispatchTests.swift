import CoreGraphics
import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

/// Todo 10's acceptance: an active set containing a music activity renders
/// `MusicExpandedView` (and similarly for timer, AI agent, charging), sized at
/// real content heights, and a set exceeding the panel scrolls rather than
/// growing the frame.
///
/// The renderer choice is asserted value-level through `expandedItemRenderer`
/// — the same function the view's `item(for:)` switch consults — because the
/// view layer has no window server under `swift test` to inspect rendered
/// view identity.
@Suite("ExpandedActivityView per-kind dispatch")
@MainActor
struct ExpandedActivityDispatchTests {
    private static let epoch = Date(timeIntervalSince1970: 0)

    private static func music() -> MusicActivity {
        MusicActivity(
            nowPlaying: NowPlaying(
                title: "Track",
                artist: "Artist",
                playbackState: .playing,
                sourceApplicationName: "Spotify"
            )
        )
    }

    private static func timer() -> TimerActivity {
        TimerActivity(
            mode: .countdown(duration: .seconds(600)),
            schedule: .started(at: epoch),
            at: epoch
        )
    }

    private static func aiAgent(progress: Double? = nil) -> AIAgentActivity {
        AIAgentActivity(
            agent: .claudeCode,
            sessionID: UUID(),
            state: .working,
            detail: "refactoring",
            progress: progress
        )
    }

    private static func charging() -> ChargingActivity {
        ChargingActivity(state: .charging)
    }

    private static func recording(_ source: RecordingSource = .screen) -> RecordingActivity {
        RecordingActivity.started(source, at: epoch)
    }

    private struct UnknownKindActivity: Activity {
        let identity = ActivityIdentity("notchflow.unknown")
        let kind = ActivityKind.fileTransfer
        let priority = ActivityPriority.normal
    }

    @Test("each concrete payload type earns its dedicated renderer")
    func concreteTypesGetDedicatedRenderers() {
        #expect(expandedItemRenderer(for: Self.music()) == .music)
        #expect(expandedItemRenderer(for: Self.timer()) == .timer)
        #expect(expandedItemRenderer(for: Self.aiAgent()) == .aiAgent)
        #expect(expandedItemRenderer(for: Self.charging()) == .charging)
        #expect(expandedItemRenderer(for: Self.recording()) == .recording)
    }

    @Test("recording copy names each live capture without naming an unknown app")
    func recordingCopyNamesTheCaptureSource() {
        #expect(recordingActivityTitleKey(for: .screen) == "Screen recording in progress")
        #expect(recordingActivityTitleKey(for: .audio) == "Microphone in use")
    }

    @Test("expanded view keeps screen and microphone capture as separate rows")
    func concurrentRecordingsRemainSeparateRows() {
        let rows = expandedRows(for: [Self.recording(.audio), Self.recording(.screen)])

        #expect(
            rows.map(\.id) == [
                RecordingActivity.identity(for: .audio).rawValue,
                RecordingActivity.identity(for: .screen).rawValue,
            ]
        )
        #expect(rows.map(\.title) == ["Microphone in use", "Screen recording in progress"])
    }

    @Test("an activity without a dedicated view keeps the generic row")
    func unknownKindFallsBackToGenericRow() {
        #expect(expandedItemRenderer(for: UnknownKindActivity()) == .genericRow)
    }

    @Test("per-kind items are sized at their real content heights, not row multiples")
    func itemHeightsMatchPerKindViews() {
        let metrics = ExpandedItemMetrics.default
        let panelMetrics = PanelMetrics.default

        let musicHeight = expandedItemHeight(for: Self.music(), metrics: metrics, panelMetrics: panelMetrics)
        #expect(
            musicHeight
                == musicExpandedSize(metrics: metrics.music, panelMetrics: panelMetrics).height
        )
        #expect(musicHeight > metrics.panel.rowHeight)

        let timerHeight = expandedItemHeight(for: Self.timer(), metrics: metrics, panelMetrics: panelMetrics)
        #expect(
            timerHeight
                == timerExpandedSize(metrics: metrics.timer, panelMetrics: panelMetrics).height
        )

        let agentHeight = expandedItemHeight(for: Self.aiAgent(), metrics: metrics, panelMetrics: panelMetrics)
        #expect(
            agentHeight
                == aiAgentExpandedSize(hasProgress: false, metrics: metrics.aiAgent, panelMetrics: panelMetrics).height
        )

        let agentWithProgress = expandedItemHeight(
            for: Self.aiAgent(progress: 0.5),
            metrics: metrics,
            panelMetrics: panelMetrics
        )
        #expect(agentWithProgress > agentHeight)

        #expect(
            expandedItemHeight(for: Self.charging(), metrics: metrics, panelMetrics: panelMetrics)
                == metrics.panel.rowHeight
        )
        #expect(
            expandedItemHeight(for: Self.recording(), metrics: metrics, panelMetrics: panelMetrics)
                == metrics.panel.rowHeight
        )
    }

    @Test("a mixed set sums its real heights plus spacing and inset")
    func mixedSetSizesByContent() {
        let metrics = ExpandedItemMetrics.default
        let panelMetrics = PanelMetrics.default
        let activities: [any Activity] = [Self.music(), Self.aiAgent(), Self.charging()]

        let size = expandedPanelSize(for: activities, metrics: metrics, panelMetrics: panelMetrics)

        let expectedHeight =
            expandedItemHeight(for: activities[0], metrics: metrics, panelMetrics: panelMetrics)
            + expandedItemHeight(for: activities[1], metrics: metrics, panelMetrics: panelMetrics)
            + expandedItemHeight(for: activities[2], metrics: metrics, panelMetrics: panelMetrics)
            + 2 * metrics.panel.rowSpacing
            + 2 * metrics.panel.contentInset

        #expect(size.height == expectedHeight)
        #expect(size.width <= panelMetrics.maximumExpandedSize.width)

        // The frame must carry the padding the view applies on both axes. A
        // width sized to the bare card squeezes every card by twice the inset,
        // which pushes trailing control buttons outside the frame and makes
        // them unclickable — a real defect this caught at runtime.
        let widest =
            activities
            .map { expandedItemWidth(for: $0, metrics: metrics, panelMetrics: panelMetrics) }
            .max() ?? 0
        #expect(size.width == widest + 2 * metrics.panel.contentInset)
    }

    @Test("a set taller than the allocated window reports overflow instead of growing")
    func overflowingSetScrolls() {
        let metrics = ExpandedItemMetrics.default
        let panelMetrics = PanelMetrics(
            maximumExpandedSize: CGSize(width: 640, height: 260),
            minimumBottomInset: 120
        )

        let fits: [any Activity] = [Self.music(), Self.aiAgent()]
        #expect(
            expandedPanelOverflowsWindow(for: fits, metrics: metrics, panelMetrics: panelMetrics)
                == false
        )
        #expect(
            expandedPanelSize(for: fits, metrics: metrics, panelMetrics: panelMetrics).height
                <= panelMetrics.maximumExpandedSize.height
        )

        let overflowingAgentCount = 5
        let overflows: [any Activity] = Array(
            repeating: Self.aiAgent(),
            count: overflowingAgentCount
        )
        #expect(
            expandedPanelOverflowsWindow(for: overflows, metrics: metrics, panelMetrics: panelMetrics)
        )
        #expect(
            expandedPanelSize(for: overflows, metrics: metrics, panelMetrics: panelMetrics).height
                == panelMetrics.maximumExpandedSize.height
        )
        #expect(
            expandedPanelSize(for: overflows, metrics: metrics, panelMetrics: panelMetrics).height
                < expandedItemHeight(for: Self.aiAgent(), metrics: metrics, panelMetrics: panelMetrics)
                * CGFloat(overflowingAgentCount)
        )
    }

    @Test("the notch inset is removed from the expanded content viewport")
    func notchInsetReducesViewport() {
        let panelMetrics = PanelMetrics.default
        let notchHeight: CGFloat = 37
        let activities: [any Activity] = (0..<6).map {
            SizedStubActivity(identity: ActivityIdentity("generic.\($0)"))
        }

        let size = expandedPanelSize(
            for: activities,
            panelMetrics: panelMetrics,
            topInset: notchHeight
        )

        #expect(size.height == panelMetrics.maximumExpandedSize.height - notchHeight)
        #expect(
            expandedPanelOverflowsWindow(
                for: activities,
                panelMetrics: panelMetrics,
                topInset: notchHeight
            )
        )
    }

    @Test("an empty set draws nothing")
    func emptySetHasZeroSize() {
        #expect(
            expandedPanelSize(for: [], metrics: .default, panelMetrics: .default) == .zero
        )
        #expect(
            expandedPanelOverflowsWindow(for: [], metrics: .default, panelMetrics: .default)
                == false
        )
    }
}

private struct SizedStubActivity: Activity {
    let identity: ActivityIdentity
    let kind = ActivityKind.fileTransfer
    let priority = ActivityPriority.normal
}
