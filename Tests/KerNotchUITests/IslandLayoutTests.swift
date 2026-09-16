import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

/// The island size setting: the two layouts it picks between, and — the part
/// that can quietly break — whether every card still fits the island it is
/// drawn in once the island and its type both grow.
@Suite("Island layout")
@MainActor
struct IslandLayoutTests {
    private static let epoch = Date(timeIntervalSince1970: 0)

    /// The notches KerNotch has to fit: the no-notch fallback, a 14" and a
    /// 16" MacBook Pro.
    nonisolated private static let notchSizes = [
        PanelMetrics.default.compactFallbackSize,
        CGSize(width: 185, height: 32),
        CGSize(width: 220, height: 38),
    ]

    private static let longText =
        "An extraordinarily long line of text that would never fit on one row of the island"

    // MARK: - Choosing a layout

    @Test("each island size resolves to its own layout")
    func sizesResolveToLayouts() {
        #expect(IslandLayout(size: .minimalist) == .minimalist)
        #expect(IslandLayout(size: .large) == .large)
        #expect(IslandLayout.minimalist != IslandLayout.large)
    }

    /// Minimalist is the island every existing user already has; choosing it
    /// must not move a single point.
    @Test("minimalist is exactly the island KerNotch has always drawn")
    func minimalistKeepsTheDefaults() {
        #expect(IslandLayout.minimalist.panel == PanelMetrics.default)
        #expect(IslandLayout.minimalist.items == ExpandedItemMetrics.default)
    }

    @Test("large grows the window budget and the card type together")
    func largeGrowsEverything() {
        let minimalist = IslandLayout.minimalist
        let large = IslandLayout.large

        #expect(large.panel.maximumExpandedSize.width > minimalist.panel.maximumExpandedSize.width)
        #expect(large.panel.maximumExpandedSize.height > minimalist.panel.maximumExpandedSize.height)
        #expect(large.panel.expandedWidthGrowth > minimalist.panel.expandedWidthGrowth)
        #expect(large.items.typeScale.title > minimalist.items.typeScale.title)
        #expect(large.items.typeScale.footnote > minimalist.items.typeScale.footnote)
        #expect(large.items.panel.rowHeight > minimalist.items.panel.rowHeight)
        #expect(large.items.music.artworkSize > minimalist.items.music.artworkSize)
        #expect(large.items.timer.controlButtonSize > minimalist.items.timer.controlButtonSize)
        #expect(large.items.aiAgent.glyphSize > minimalist.items.aiAgent.glyphSize)
    }

    /// Scaled metrics are rounded to whole points so hairlines and glyph edges
    /// stay on the pixel grid.
    @Test("large metrics land on whole points")
    func largeMetricsAreWholePoints() {
        let items = IslandLayout.large.items
        let values = [
            items.typeScale.title, items.typeScale.detail, items.typeScale.nestedTitle,
            items.typeScale.nestedDetail, items.typeScale.footnote,
            items.panel.rowHeight, items.panel.rowSpacing, items.panel.contentInset,
            items.music.artworkSize, items.music.transportButtonSize,
            items.timer.timeSize, items.timer.controlButtonSize,
            items.aiAgent.glyphSize, items.aiAgent.subagentRowHeight,
            items.aiAgent.subagentSeparatorHeight,
        ]

        #expect(values.allSatisfy { $0 == $0.rounded() && $0 >= 1 })
    }

    @Test("the large island is wider than the minimalist one on every notch", arguments: notchSizes)
    func largeIslandIsWider(notch: CGSize) {
        let minimalist = expandedPanelWidth(notchSize: notch, panelMetrics: IslandLayout.minimalist.panel)
        let large = expandedPanelWidth(notchSize: notch, panelMetrics: IslandLayout.large.panel)

        #expect(large > minimalist)
    }

    /// The surface is wider than its content by one top flare on each side, and
    /// as tall as the neck plus the content — so a saturated island has to fit
    /// the window exactly, flare and neck included, or its edges are clipped.
    @Test(
        "a saturated expanded surface fits the window allocated for it",
        arguments: [IslandSize.minimalist, .large], notchSizes
    )
    func surfaceFitsWindow(size: IslandSize, notch: CGSize) {
        let layout = IslandLayout(size: size)
        let saturating = Self.everyKind() + Self.chargingRows(40)
        #expect(
            expandedPanelOverflowsWindow(
                for: saturating,
                metrics: layout.items,
                panelMetrics: layout.panel,
                topInset: notch.height
            )
        )
        let content = expandedPanelSize(
            for: saturating,
            notchSize: notch,
            metrics: layout.items,
            panelMetrics: layout.panel,
            topInset: notch.height
        )
        let surface = ConnectedIslandGeometry(
            compactSize: balancedCompactPillSize(leadingSlotCount: 2, trailingSlotCount: 2, notchSize: notch),
            expandedContentSize: content
        ).expandedSize

        #expect(surface.width <= layout.panel.maximumExpandedSize.width)
        #expect(surface.height <= layout.panel.maximumExpandedSize.height)
    }

    /// A 13" MacBook Air at a larger-text scaling is shorter than the large
    /// island's budget plus the Dock inset. Fitted to that screen, the island
    /// has to end at the window's bottom edge and scroll the rest, not draw
    /// rows past an edge nothing can show.
    @Test("on a short screen the large island ends at the window and scrolls")
    func largeIslandScrollsOnAShortScreen() {
        let notch = CGSize(width: 185, height: 32)
        let shortScreen = ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 1024, height: 640),
            safeAreaInsets: ScreenSafeAreaInsets(top: notch.height),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 640 - notch.height, width: 419.5, height: notch.height),
            auxiliaryTopRightArea: CGRect(x: 604.5, y: 640 - notch.height, width: 419.5, height: notch.height),
            isBuiltIn: true
        )
        let window = panelFrame(for: shortScreen, metrics: IslandLayout.large.panel)
        let fitted = IslandLayout.large.fitted(to: shortScreen)
        let rows = Self.chargingRows(10)
        let unfittedHeight = expandedPanelSize(
            for: rows,
            notchSize: notch,
            metrics: fitted.items,
            panelMetrics: IslandLayout.large.panel,
            topInset: notch.height
        ).height
        #expect(unfittedHeight + notch.height > window.height, "the fixture no longer reaches past the window")

        let content = expandedPanelSize(
            for: rows,
            notchSize: notch,
            metrics: fitted.items,
            panelMetrics: fitted.panel,
            topInset: notch.height
        )

        #expect(content.height + notch.height <= window.height)
        #expect(
            expandedPanelOverflowsWindow(
                for: rows,
                metrics: fitted.items,
                panelMetrics: fitted.panel,
                topInset: notch.height
            )
        )
    }

    @Test("a layout with no screen to fit stays as chosen")
    func layoutWithoutScreenIsUnchanged() {
        #expect(IslandLayout.large.fitted(to: nil) == .large)
    }

    /// The large island holds as many rows before scrolling as the minimalist
    /// one does, so growing the type does not cost the user visible activities.
    @Test("the large island does not scroll sooner than the minimalist one")
    func largeIslandDoesNotScrollSooner() {
        func rowsBeforeScrolling(_ layout: IslandLayout) -> Int {
            var rows = 1
            while rows < 200,
                expandedPanelOverflowsWindow(
                    for: Self.chargingRows(rows),
                    metrics: layout.items,
                    panelMetrics: layout.panel,
                    topInset: 38
                ) == false
            {
                rows += 1
            }
            return rows
        }

        #expect(rowsBeforeScrolling(.large) >= rowsBeforeScrolling(.minimalist))
    }

    // MARK: - Every card fits

    /// Guards the measurement itself: a card squeezed below its fixed parts —
    /// artwork, controls, insets — reports a width wider than it was offered.
    /// Without this, a measuring method that always echoed the proposal back
    /// would pass every fit test below.
    @Test("a card offered too little width reports the width it needs")
    func measurementDetectsOverflow() {
        let tooNarrow: CGFloat = 60
        let fitted = Self.fittedSize(
            of: MusicExpandedView(activity: Self.music()),
            width: tooNarrow
        )

        #expect(fitted.width > tooNarrow)
    }

    /// Each card lays out in a row whose height the panel reserves up front, so
    /// the width is where a larger type scale can break a card: fixed parts —
    /// artwork, controls, glyph columns — that no longer fit beside each other.
    @Test(
        "every card fits the width of the island it is drawn in",
        arguments: [IslandSize.minimalist, .large], notchSizes
    )
    func everyCardFits(size: IslandSize, notch: CGSize) {
        let layout = IslandLayout(size: size)
        let items = layout.items
        let panelWidth = expandedPanelSize(
            for: [Self.music()],
            notchSize: notch,
            metrics: items,
            panelMetrics: layout.panel
        ).width
        let available = panelWidth - items.panel.contentInset * 2

        let cards: [(name: String, view: AnyView)] = [
            (
                "music",
                AnyView(MusicExpandedView(activity: Self.music(), metrics: items.music, panelMetrics: layout.panel))
            ),
            (
                "timer",
                AnyView(TimerExpandedView(activity: Self.timer(), metrics: items.timer, panelMetrics: layout.panel))
            ),
            (
                "agent",
                AnyView(AIAgentActivityView(activity: Self.agent(), metrics: items.aiAgent, panelMetrics: layout.panel))
            ),
            ("charging", AnyView(ChargingActivityView(activity: Self.charging(), metrics: items.panel))),
            ("recording", AnyView(RecordingActivityView(activity: Self.recording(), metrics: items.panel))),
            ("discord", AnyView(DiscordCallActivityView(activity: Self.discordCall(), metrics: items.panel))),
        ]

        for card in cards {
            let fitted = Self.fittedSize(of: card.view, width: available)

            // The hosting controller reports whole points, rounding up.
            #expect(
                fitted.width <= available.rounded(.up),
                "\(card.name) needs \(fitted.width)pt of \(available)pt"
            )
        }
    }

    /// A card's height is reserved from its metrics, and its text is laid
    /// inside that height. Scaling every metric by the same factor keeps each
    /// card's text-to-row proportion, so a card that fits the minimalist island
    /// fits the large one — rounding to whole points moves nothing by more than
    /// half a point.
    @Test("large scales every card metric by one factor")
    func largeScalesUniformly() {
        let factor = ExpandedItemMetrics.largeScale
        let pairs: [(CGFloat, CGFloat)] = [
            (ExpandedItemMetrics.default.typeScale.title, ExpandedItemMetrics.large.typeScale.title),
            (ExpandedItemMetrics.default.typeScale.detail, ExpandedItemMetrics.large.typeScale.detail),
            (ExpandedItemMetrics.default.typeScale.footnote, ExpandedItemMetrics.large.typeScale.footnote),
            (ExpandedItemMetrics.default.panel.rowHeight, ExpandedItemMetrics.large.panel.rowHeight),
            (ExpandedItemMetrics.default.panel.titleSize, ExpandedItemMetrics.large.panel.titleSize),
            (ExpandedItemMetrics.default.music.artworkSize, ExpandedItemMetrics.large.music.artworkSize),
            (ExpandedItemMetrics.default.music.titleSize, ExpandedItemMetrics.large.music.titleSize),
            (ExpandedItemMetrics.default.music.subtitleSize, ExpandedItemMetrics.large.music.subtitleSize),
            (ExpandedItemMetrics.default.timer.glyphSize, ExpandedItemMetrics.large.timer.glyphSize),
            (ExpandedItemMetrics.default.timer.timeSize, ExpandedItemMetrics.large.timer.timeSize),
            (ExpandedItemMetrics.default.aiAgent.glyphSize, ExpandedItemMetrics.large.aiAgent.glyphSize),
            (ExpandedItemMetrics.default.aiAgent.titleSize, ExpandedItemMetrics.large.aiAgent.titleSize),
            (
                ExpandedItemMetrics.default.aiAgent.subagentRowHeight,
                ExpandedItemMetrics.large.aiAgent.subagentRowHeight
            ),
        ]

        for (minimalist, large) in pairs {
            #expect(abs(large - minimalist * factor) <= 0.5, "\(minimalist) scaled to \(large)")
        }
    }

    // MARK: - Fixtures

    /// The size a card takes when offered `width`, drawn the way the island
    /// draws it: sharing the island's surface rather than painting its own.
    private static func fittedSize(of view: some View, width: CGFloat) -> CGSize {
        let controller = NSHostingController(
            rootView: view.sharingIslandSurface().environment(\.colorScheme, .dark)
        )
        return controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private static func everyKind() -> [any Activity] {
        [music(), timer(), agent(), charging(), recording(), discordCall()]
    }

    private static func chargingRows(_ count: Int) -> [any Activity] {
        (0..<count).map { _ in ChargingActivity(state: .charging) as any Activity }
    }

    private static func music() -> MusicActivity {
        MusicActivity(
            nowPlaying: NowPlaying(
                title: longText,
                artist: longText,
                playbackState: .playing,
                sourceApplicationName: "Spotify"
            )
        )
    }

    private static func timer() -> TimerActivity {
        TimerActivity(
            mode: .countdown(duration: .seconds(36_000)),
            schedule: .started(at: epoch),
            at: epoch
        )
    }

    private static func agent() -> AIAgentActivity {
        AIAgentActivity(
            agent: .claudeCode,
            sessionID: UUID(),
            state: .working,
            detail: longText,
            progress: 0.4
        )
    }

    private static func charging() -> ChargingActivity {
        ChargingActivity(state: .charging)
    }

    private static func recording() -> RecordingActivity {
        RecordingActivity.started(.screen, at: epoch)
    }

    private static func discordCall() -> DiscordCallActivity {
        DiscordCallActivity(
            channel: DiscordVoiceChannel(name: longText, serverName: longText),
            isMuted: true
        )
    }
}
