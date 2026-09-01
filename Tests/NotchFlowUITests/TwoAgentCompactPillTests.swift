import CoreGraphics
import Foundation
import NotchFlowCore
import Testing

@testable import NotchFlowUI

/// The reported defect, end to end: two agents active at once, and the icon
/// nearest the notch never drawn.
///
/// Runs the real path — envelope, manager, compact presentation, slot layout,
/// pill geometry — rather than asserting on the geometry function alone, so a
/// regression anywhere along it fails here.
@Suite("Two agents in the compact pill")
@MainActor
struct TwoAgentCompactPillTests {
    private static let notch = CGSize(width: 200, height: 32)

    @Test("both agent icons fit inside the drawn pill")
    func twoAgentsBothFit() {
        let manager = ActivityManager()
        manager.register(Self.agent(.claudeCode, state: .usingTool))
        manager.register(Self.agent(.opencode, state: .waitingForUser))

        let presentation = manager.compactPresentation
        let layout = compactSlotLayout(for: presentation)
        let metrics = CompactPillMetrics()
        let size = compactPillSize(for: layout, notchSize: Self.notch, metrics: metrics)

        #expect(layout.trailing.count == 2, "both agents should occupy the trailing side")

        // What the view lays out: padding, the (empty) leading row, the notch
        // plus one gap for the occupied flank, then the trailing row.
        let trailingNeeds =
            CGFloat(layout.trailing.count) * metrics.slotWidth
            + CGFloat(layout.trailing.count - 1) * metrics.slotSpacing
        let expected =
            metrics.edgeInset * 2 + Self.notch.width + metrics.slotSpacing + trailingNeeds

        #expect(size.width == expected, "the trailing flank is not drawn at full width")
    }

    /// With nothing on the leading side the pill must not grow an empty stub
    /// there — the whole point of sizing each flank to its own contents.
    @Test("an empty leading side adds no width")
    func emptyLeadingSideCostsNothing() {
        let manager = ActivityManager()
        manager.register(Self.agent(.claudeCode, state: .usingTool))
        manager.register(Self.agent(.opencode, state: .usingTool))

        let layout = compactSlotLayout(for: manager.compactPresentation)
        let metrics = CompactPillMetrics()
        let pill = compactPillGeometry(for: layout, notchSize: Self.notch, metrics: metrics)
        let balanced = balancedCompactPillSize(
            for: manager.compactPresentation,
            notchSize: Self.notch,
            metrics: metrics
        )

        #expect(layout.leading.isEmpty)
        #expect(pill.size.width < balanced.width)
        // Leaning right, so the drawn pill is shifted right to keep the notch
        // region over the hardware cutout.
        #expect(pill.drawingOffset > 0)
    }

    @Test("the pill widens when a second agent appears")
    func pillGrowsWithTheSecondAgent() {
        let manager = ActivityManager()
        manager.register(Self.agent(.claudeCode, state: .usingTool))
        let oneAgent = compactPillSize(
            for: compactSlotLayout(for: manager.compactPresentation),
            notchSize: Self.notch
        )

        manager.register(Self.agent(.opencode, state: .usingTool))
        let twoAgents = compactPillSize(
            for: compactSlotLayout(for: manager.compactPresentation),
            notchSize: Self.notch
        )

        #expect(twoAgents.width > oneAgent.width)
    }

    /// Sessions of one agent collapse to a single icon, so two concurrent Claude
    /// sessions must not consume the slot the second agent needs.
    @Test("two sessions of one agent still draw one icon")
    func sessionsOfOneAgentShareASlot() {
        let manager = ActivityManager()
        manager.register(Self.agent(.claudeCode, state: .usingTool))
        manager.register(Self.agent(.claudeCode, state: .working))

        let layout = compactSlotLayout(for: manager.compactPresentation)

        #expect(layout.trailing.count == 1)
    }

    /// Music beside two agents: the standard side and the agent side are sized
    /// independently, and the busier one sets both flanks.
    @Test("an activity beside two agents still fits")
    func standardActivityBesideTwoAgents() {
        let manager = ActivityManager()
        manager.register(MusicActivity(nowPlaying: Self.nowPlaying))
        manager.register(Self.agent(.claudeCode, state: .usingTool))
        manager.register(Self.agent(.opencode, state: .usingTool))

        let layout = compactSlotLayout(for: manager.compactPresentation)
        let metrics = CompactPillMetrics()
        let size = compactPillSize(for: layout, notchSize: Self.notch, metrics: metrics)

        func flank(_ slots: Int) -> CGFloat {
            slots > 0
                ? CGFloat(slots) * metrics.slotWidth + CGFloat(slots - 1) * metrics.slotSpacing
                : 0
        }
        let expected =
            metrics.edgeInset * 2
            + flank(layout.leading.count) + metrics.slotSpacing
            + Self.notch.width
            + metrics.slotSpacing + flank(layout.trailing.count)

        #expect(layout.leading.isEmpty == false)
        #expect(layout.trailing.count == 2)
        #expect(size.width == expected)
    }

    private static func agent(_ id: IPCAgentID, state: AIAgentState) -> AIAgentActivity {
        AIAgentActivity(
            agent: id,
            sessionID: UUID(),
            state: state,
            detail: "Working"
        )
    }

    private static var nowPlaying: NowPlaying {
        NowPlaying(
            title: "Windowlicker",
            artist: "Aphex Twin",
            playbackState: .playing,
            sourceApplicationName: "Spotify"
        )
    }
}
