import CoreGraphics
import Foundation
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

/// The rule that keeps the island's shape and its contents on one clock.
///
/// The reported defect: the icons animated while the black surface behind them,
/// the mask that clips it and its offset onto the notch were assigned outright,
/// so an icon arriving read as the island snapping wider and the glyph catching
/// up, and an icon leaving was clipped in half by a pill that had already closed
/// over it.
@Suite("Island content motion")
@MainActor
struct IslandContentMotionTests {
    private static let motion = IslandMotion.default

    // MARK: - Which way the island is moving

    @Test("a wider pill is the island growing")
    func widerIsGrowing() {
        let change = islandExtentChange(
            from: CGSize(width: 260, height: 32),
            to: CGSize(width: 288, height: 32)
        )

        #expect(change == .growing)
    }

    /// The expanded panel grows downwards, so height counts for as much as
    /// width: a card arriving is the island opening up to make room for it.
    @Test("a taller panel is the island growing")
    func tallerIsGrowing() {
        let change = islandExtentChange(
            from: CGSize(width: 400, height: 120),
            to: CGSize(width: 400, height: 190)
        )

        #expect(change == .growing)
    }

    @Test("a narrower pill is the island shrinking")
    func narrowerIsShrinking() {
        let change = islandExtentChange(
            from: CGSize(width: 288, height: 32),
            to: CGSize(width: 260, height: 32)
        )

        #expect(change == .shrinking)
    }

    // MARK: - Who waits for whom

    /// Opening, the shape goes first, so an icon never appears in a space the
    /// island has not made yet.
    @Test("growing, the island leads and its contents follow")
    func growingLeadsWithTheShape() {
        let motion = islandContentMotion(in: .compact, change: .growing)

        #expect(motion.containerDelay == 0)
        #expect(motion.contentDelay == Self.motion.contentLead)
    }

    /// Closing, the contents go first, so the shape never closes across
    /// something still drawn inside it.
    @Test("shrinking, the contents leave and the island follows")
    func shrinkingLeadsWithTheContents() {
        let motion = islandContentMotion(in: .compact, change: .shrinking)

        #expect(motion.contentDelay == 0)
        #expect(motion.containerDelay == Self.motion.contentLead)
    }

    @Test("the lead is short enough to read as one movement")
    func theLeadIsShort() {
        #expect(Self.motion.contentLead == 0.08)
    }

    @Test("both sides move on the island's own spring")
    func bothSidesShareTheIslandsSpring() {
        let motion = islandContentMotion(in: .compact, change: .growing)

        #expect(
            motion.curve
                == .spring(
                    response: Self.motion.springResponse,
                    dampingFraction: Self.motion.springDamping
                )
        )
        #expect(motion.curve == islandAnimationCurve(from: .compact, to: .expanded))
    }

    /// A control inside the island knows which way it is about to move before
    /// anything has, so it re-points the motion rather than reading the
    /// direction of whatever changed last.
    @Test("a change can be re-pointed in the other direction")
    func changingDirection() {
        let growing = islandContentMotion(in: .expanded, change: .growing)
        let shrinking = growing.changing(to: .shrinking)

        #expect(shrinking.change == .shrinking)
        #expect(shrinking.curve == growing.curve)
        #expect(shrinking.containerDelay == Self.motion.contentLead)
    }

    // MARK: - When nothing may move

    /// The idle budget in `docs/02-performance-contract.md`: a hidden island
    /// schedules no animation at all.
    @Test("a hidden island animates nothing")
    func hiddenIslandIsStill() {
        let motion = islandContentMotion(in: .hidden, change: .growing)

        #expect(motion == .still)
        #expect(motion.container == nil)
        #expect(motion.content == nil)
    }

    /// Standing the island still is the whole point of the watchdog's degrade,
    /// so a change made while it is degraded is applied rather than animated.
    @Test("a degraded island animates nothing")
    func suspendedIslandIsStill() {
        let motion = islandContentMotion(in: .compact, change: .growing, isMotionSuspended: true)

        #expect(motion == .still)
    }

    /// Reduce Motion removes the travel, and staggering two fades would read as
    /// a flicker rather than as one thing following another.
    @Test("Reduce Motion fades both sides together")
    func reduceMotionDropsTheLead() {
        let motion = islandContentMotion(in: .compact, change: .growing, reduceMotion: true)

        #expect(motion.curve == .crossFade(duration: Self.motion.reducedMotionCrossFadeDuration))
        #expect(motion.containerDelay == 0)
        #expect(motion.contentDelay == 0)
    }

    // MARK: - The size the direction is read from

    /// The island's drawn size is one calculation, used both to draw it and to
    /// decide which way a change moves it. Two of them could disagree.
    @Test("an arriving icon makes the compact island wider")
    func anArrivingIconWidensTheIsland() {
        let manager = ActivityManager()
        manager.register(
            MusicActivity(
                nowPlaying: NowPlaying(title: "Windowlicker", artist: "Aphex Twin", playbackState: .playing)
            ),
            at: Date(timeIntervalSince1970: 1)
        )
        let before = Self.extent(manager, state: .compact)

        manager.register(DiscordCallActivity(channel: nil, isMuted: false), at: Date(timeIntervalSince1970: 2))
        let after = Self.extent(manager, state: .compact)

        #expect(islandExtentChange(from: before, to: after) == .growing)
    }

    /// The music icon that has timed out is not drawn, so the island it is
    /// taken off is narrower — which is what makes its departure a shrink.
    @Test("hiding a paused track makes the compact island narrower")
    func hidingATrackNarrowsTheIsland() {
        let manager = ActivityManager()
        manager.register(
            MusicActivity(
                nowPlaying: NowPlaying(title: "Windowlicker", artist: "Aphex Twin", playbackState: .paused)
            ),
            at: Date(timeIntervalSince1970: 1)
        )
        manager.register(DiscordCallActivity(channel: nil, isMuted: false), at: Date(timeIntervalSince1970: 2))

        let shown = Self.extent(manager, state: .compact)
        let hidden = Self.extent(manager, state: .compact, hiding: [MusicActivity.identity.rawValue])

        #expect(islandExtentChange(from: shown, to: hidden) == .shrinking)
    }

    @Test("opening the island is a growth of its own")
    func expandingGrowsTheIsland() {
        let manager = ActivityManager()
        manager.register(
            MusicActivity(
                nowPlaying: NowPlaying(title: "Windowlicker", artist: "Aphex Twin", playbackState: .playing)
            )
        )

        let compact = Self.extent(manager, state: .compact)
        let expanded = Self.extent(manager, state: .expanded)

        #expect(islandExtentChange(from: compact, to: expanded) == .growing)
    }

    private static func extent(
        _ manager: ActivityManager,
        state: PresentationState,
        hiding hiddenMusicSlotIDs: Set<String> = []
    ) -> CGSize {
        islandSurfaceSize(
            IslandExtentInput(
                state: state,
                compact: manager.compactPresentation,
                hiddenMusicSlotIDs: hiddenMusicSlotIDs,
                pet: nil,
                expanded: manager.expandedActivities,
                disclosedInstances: [],
                registrationTimes: manager.registrationTimes,
                notchSize: CGSize(width: 185, height: 32),
                layout: .minimalist
            )
        )
    }
}
