import CoreGraphics
import Foundation
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

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
        ChargingActivity(state: .charging, level: BatteryLevel(fraction: 0.5))
    }

    private static func recording(_ source: RecordingSource = .screen) -> RecordingActivity {
        RecordingActivity.started(source, at: epoch)
    }

    private struct UnknownKindActivity: Activity {
        let identity = ActivityIdentity("kernotch.unknown")
        let kind = ActivityKind.timer
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

    @Test("per-kind items are sized at their real content heights")
    func itemHeightsMatchPerKindViews() {
        let metrics = ExpandedItemMetrics.default
        let panelMetrics = PanelMetrics.default

        let musicHeight = expandedItemHeight(for: Self.music(), metrics: metrics, panelMetrics: panelMetrics)
        #expect(
            musicHeight
                == musicExpandedSize(metrics: metrics.music, panelMetrics: panelMetrics).height
        )

        let timerHeight = expandedItemHeight(for: Self.timer(), metrics: metrics, panelMetrics: panelMetrics)
        #expect(
            timerHeight
                == timerExpandedSize(metrics: metrics.timer, panelMetrics: panelMetrics).height
        )

        // The agent card is measured by its own view rather than assumed to be a
        // row. It was measured at `rowHeight` while a grouped view intercepted
        // every agent activity and this number went unused; drawing sessions as
        // their own cards made the shortfall visible as clipping at the bottom
        // of the island.
        let agentHeight = expandedItemHeight(for: Self.aiAgent(), metrics: metrics, panelMetrics: panelMetrics)
        #expect(
            agentHeight
                == aiAgentExpandedSize(
                    hasProgress: false,
                    metrics: metrics.aiAgent,
                    panelMetrics: panelMetrics
                ).height
        )
        // Every card stands at the island's one row height, so the panel reads
        // as a list rather than as a stack of differently sized boxes.
        #expect(musicHeight == metrics.panel.rowHeight)
        #expect(timerHeight == metrics.panel.rowHeight)
        #expect(agentHeight == metrics.panel.rowHeight)
        #expect(metrics.panel.rowHeight == IslandRowGrammar.default.rowHeight)

        let agentWithProgress = expandedItemHeight(
            for: Self.aiAgent(progress: 0.5),
            metrics: metrics,
            panelMetrics: panelMetrics
        )
        #expect(agentWithProgress > agentHeight, "the progress bar is drawn but not measured")

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

        // The width is the pill's, not the widest card's. Cards share the
        // island's surface and stretch to whatever the panel gives them, and
        // every card here is narrower than the panel — so a width fitted to the
        // contents only made the island a different shape depending on what
        // happened to be running.
        #expect(
            size.width
                == expandedPanelWidth(
                    notchSize: panelMetrics.compactFallbackSize,
                    panelMetrics: panelMetrics
                )
        )
        #expect(
            size.width
                > activities
                .map { expandedItemWidth(for: $0, metrics: metrics, panelMetrics: panelMetrics) }
                .max() ?? 0,
            "every card has room to breathe inside the panel"
        )
    }

    /// The panel is one width whatever it happens to hold: opening the island on
    /// a track and opening it on an agent must not produce two different shapes.
    @Test("the panel is the same width whatever it holds")
    func panelWidthDoesNotFollowItsContents() {
        let music = expandedPanelSize(for: [Self.music()])
        let agent = expandedPanelSize(for: [Self.aiAgent()])
        let mixed = expandedPanelSize(for: [Self.music(), Self.aiAgent(), Self.charging()])

        #expect(music.width == agent.width)
        #expect(agent.width == mixed.width)
    }

    /// It grows out of the pill, so it has to be wider than the pill it grows
    /// from and still fit the window that was allocated for it.
    @Test("the panel is the compact pill, grown")
    func panelIsThePillGrown() {
        let panelMetrics = PanelMetrics.default
        let notch = panelMetrics.compactFallbackSize
        let pill = compactPillSize(
            leadingSlotCount: expandedPanelReferenceSlotCount,
            trailingSlotCount: expandedPanelReferenceSlotCount,
            notchSize: notch
        )
        let width = expandedPanelWidth(notchSize: notch, panelMetrics: panelMetrics)

        #expect(width > pill.width)
        #expect(width <= panelMetrics.maximumExpandedSize.width)
    }

    /// A wider notch is a wider pill and therefore a wider panel: the constant
    /// that would be right on one Mac is wrong on the next.
    @Test("a wider notch widens the panel")
    func aWiderNotchWidensThePanel() {
        let narrow = expandedPanelWidth(notchSize: CGSize(width: 180, height: 32))
        let wide = expandedPanelWidth(notchSize: CGSize(width: 220, height: 32))

        #expect(wide > narrow)
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

        let overflowingItemCount = 10
        let overflows: [any Activity] = (0..<overflowingItemCount).map {
            SizedStubActivity(identity: ActivityIdentity("overflow.\($0)"))
        }
        #expect(
            expandedPanelOverflowsWindow(for: overflows, metrics: metrics, panelMetrics: panelMetrics)
        )
        #expect(
            expandedPanelSize(for: overflows, metrics: metrics, panelMetrics: panelMetrics).height
                == panelMetrics.maximumExpandedSize.height
        )
        #expect(
            expandedPanelSize(for: overflows, metrics: metrics, panelMetrics: panelMetrics).height
                < metrics.panel.rowHeight * CGFloat(overflowingItemCount)
        )
    }

    @Test("the notch inset is removed from the expanded content viewport")
    func notchInsetReducesViewport() {
        let panelMetrics = PanelMetrics.default
        let notchHeight: CGFloat = 37
        // Derived rather than hard-coded: the point is that the inset shrinks
        // the viewport, and a fixed count silently stops overflowing the day
        // the panel's maximum height changes.
        let metrics = ExpandedItemMetrics.default
        let rowsToOverflow =
            Int(
                ((panelMetrics.maximumExpandedSize.height - notchHeight)
                    / (metrics.panel.rowHeight + metrics.panel.rowSpacing)).rounded(.up)
            ) + 1
        let activities: [any Activity] = (0..<rowsToOverflow).map {
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

    // MARK: - One type scale across every card

    /// Four cards stacked on one surface used to read as four designs: the
    /// generic row set its label from `symbolSize` — the *glyph* budget — and
    /// came out at 15pt, music picked 13, the agent card 12 and the timer 11.
    ///
    /// A card's headline says what it is; every card says that, so every card
    /// says it at one size.
    @Test("every card draws its headline at the shared title size")
    func everyCardSharesTheTitleSize() {
        let scale = IslandTypeScale.default
        let metrics = ExpandedItemMetrics.default

        #expect(metrics.panel.titleSize == scale.title, "the generic row, charging and recording")
        #expect(metrics.music.titleSize == scale.title)
        #expect(metrics.timer.timeSize == scale.title, "the clock face is the timer card's headline")
        #expect(metrics.aiAgent.titleSize == scale.title)
    }

    /// The defect this grammar exists to close: every card carried its own copy
    /// of these numbers and they had drifted, so a recording glyph was 15pt
    /// beside a 24pt agent logo and three cards started their text at three
    /// different distances from the island's edge.
    @Test("every card takes its shared measures from one grammar")
    func everyCardSharesOneGrammar() {
        let grammar = IslandRowGrammar.default
        let metrics = ExpandedItemMetrics.default

        #expect(metrics.panel.symbolColumnWidth == grammar.iconSize, "the generic row, charging and recording")
        #expect(metrics.music.artworkSize == grammar.iconSize)
        #expect(metrics.timer.glyphSize == grammar.iconSize)
        #expect(metrics.aiAgent.glyphSize == grammar.iconSize)

        for inset in [
            metrics.panel.contentInset, metrics.music.contentInset,
            metrics.timer.contentInset, metrics.aiAgent.contentInset,
        ] {
            #expect(inset == grammar.contentInset)
        }

        for spacing in [
            metrics.panel.columnSpacing, metrics.music.columnSpacing,
            metrics.timer.columnSpacing, metrics.aiAgent.columnSpacing,
        ] {
            #expect(spacing == grammar.columnSpacing)
        }

        for width in [
            metrics.panel.width, metrics.music.width,
            metrics.timer.width, metrics.aiAgent.width,
        ] {
            #expect(width == grammar.width)
        }

        #expect(metrics.music.transportButtonSize == grammar.controlButtonSize)
        #expect(metrics.timer.controlButtonSize == grammar.controlButtonSize)
        #expect(metrics.music.transportSymbolSize == grammar.controlSymbolSize)
        #expect(metrics.timer.controlSymbolSize == grammar.controlSymbolSize)
    }

    /// What the eye actually reads: every card's text begins the same distance
    /// from the island's edge, whatever is drawn beside it.
    @Test("every card starts its text in the same place")
    func everyCardStartsItsTextInOnePlace() {
        let metrics = ExpandedItemMetrics.default
        let grammar = IslandRowGrammar.default
        let expected = grammar.contentInset + grammar.iconSize + grammar.columnSpacing

        let starts = [
            metrics.panel.contentInset + metrics.panel.symbolColumnWidth + metrics.panel.columnSpacing,
            metrics.music.contentInset + metrics.music.artworkSize + metrics.music.columnSpacing,
            metrics.timer.contentInset + metrics.timer.glyphSize + metrics.timer.columnSpacing,
            metrics.aiAgent.contentInset + metrics.aiAgent.glyphSize + metrics.aiAgent.columnSpacing,
        ]

        #expect(starts.allSatisfy { $0 == expected })
    }

    /// The same for the second line every card carries.
    @Test("every card draws its secondary line at the shared detail size")
    func everyCardSharesTheDetailSize() {
        let scale = IslandTypeScale.default
        let metrics = ExpandedItemMetrics.default

        #expect(metrics.panel.detailSize == scale.detail)
        #expect(metrics.music.subtitleSize == scale.detail)
        #expect(metrics.timer.labelSize == scale.detail)
        #expect(metrics.aiAgent.detailSize == scale.detail)
    }

    /// Nesting steps the same pair down rather than inventing a third
    /// relationship, so a sub-agent row reads as subordinate to its card without
    /// introducing a size nothing else uses.
    @Test("a nested row steps the same pair down")
    func nestedRowsStepTheScaleDown() {
        let scale = IslandTypeScale.default
        let aiAgent = AIAgentViewMetrics.default

        #expect(aiAgent.subagentNameSize == scale.nestedTitle)
        #expect(aiAgent.subagentDetailSize == scale.nestedDetail)
        #expect(scale.nestedTitle < scale.title)
        #expect(scale.nestedDetail < scale.detail)
        #expect(scale.detail < scale.title)
    }

    /// The row's label must never be sized from the glyph budget again: they
    /// answer to different things, and tying them is what made a mic label three
    /// points larger than every card beside it.
    @Test("a row's label is not sized from its glyph")
    func rowLabelIsIndependentOfItsGlyph() {
        let widened = ExpandedPanelMetrics(symbolSize: 40)

        #expect(widened.titleSize == IslandTypeScale.default.title)
    }
}

private struct SizedStubActivity: Activity {
    let identity: ActivityIdentity
    let kind = ActivityKind.timer
    let priority = ActivityPriority.normal
}
