import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

@Suite("CompactActivityView")
@MainActor
struct CompactActivityViewTests {
    private struct StubActivity: Activity {
        let identity: ActivityIdentity
        let kind: ActivityKind
        let priority: ActivityPriority
    }

    private static func activity(
        _ name: String,
        _ kind: ActivityKind,
        _ priority: ActivityPriority
    ) -> StubActivity {
        StubActivity(identity: ActivityIdentity(name), kind: kind, priority: priority)
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

    @Test("renders one slot per activity in the manager's order")
    func slotsFollowManagerOrder() {
        let slots = compactSlots(for: Self.workedExample().compactPresentation)

        #expect(slots.map(\.id) == ["timer", "transfer", "music"])
        #expect(slots.allSatisfy { $0.overflowCount == nil })
    }

    @Test("replaces the last slot with an overflow indicator past capacity")
    func overflowSlotReplacesTheLastActivity() {
        let manager = Self.workedExample()
        manager.register(
            Self.activity("recording", .recording, .high),
            at: Date(timeIntervalSince1970: 4)
        )

        let slots = compactSlots(for: manager.compactPresentation)

        #expect(slots.count == 3)
        #expect(slots.dropLast().map(\.id) == ["timer", "recording"])
        #expect(slots.last?.overflowCount == 2)
        #expect(slots.last?.label == "+2")
    }

    @Test("renders nothing when no activity is active")
    func emptySetRendersNoSlots() {
        #expect(compactSlots(for: ActivityManager().compactPresentation).isEmpty)
    }

    @Test("splits the slots around the notch, reading order first")
    func slotsFlankTheNotch() {
        let layout = compactSlotLayout(for: Self.workedExample().compactPresentation)

        #expect(layout.leading.map(\.id) == ["timer", "transfer"])
        #expect(layout.trailing.map(\.id) == ["music"])
    }

    @Test("keeps the overflow indicator on the trailing side")
    func overflowSitsLast() {
        let manager = Self.workedExample()
        manager.register(
            Self.activity("recording", .recording, .high),
            at: Date(timeIntervalSince1970: 4)
        )

        let layout = compactSlotLayout(for: manager.compactPresentation)

        #expect(layout.trailing.last?.overflowCount == 2)
    }

    @Test("keeps at most two AI agents together at the far right")
    func agentsUseTrailingRegion() {
        let manager = ActivityManager()
        manager.register(Self.activity("timer", .timer, .high), at: Date(timeIntervalSince1970: 1))
        manager.register(Self.aiAgent(.claudeCode), at: Date(timeIntervalSince1970: 2))
        manager.register(Self.aiAgent(.codex), at: Date(timeIntervalSince1970: 3))
        manager.register(Self.aiAgent(.opencode), at: Date(timeIntervalSince1970: 4))

        let layout = compactSlotLayout(for: manager.compactPresentation)

        #expect(layout.leading.map(\.id) == ["timer"])
        #expect(layout.trailing.compactMap(\.aiAgentID) == [.codex, .opencode])
    }

    @Test("gives every activity kind its own symbol and spoken label")
    func everyKindIsDistinguishable() {
        let symbols = ActivityKind.allCases.map(compactSymbolName)
        let labels = ActivityKind.allCases.map(compactAccessibilityLabel)

        #expect(Set(symbols).count == ActivityKind.allCases.count)
        #expect(labels.allSatisfy { $0.isEmpty == false })
    }

    @Test("screen recording uses a source-specific animated display indicator")
    func screenRecordingUsesDisplayIndicator() throws {
        let manager = ActivityManager()
        manager.register(
            RecordingActivity.started(.screen, at: Date(timeIntervalSince1970: 1))
        )

        let slot = try #require(compactSlots(for: manager.compactPresentation).first)

        #expect(slot.recordingSource == .screen)
        #expect(slot.symbolName == "display")
    }

    @Test("microphone recording stays distinct from screen recording")
    func microphoneRecordingUsesAudioIndicator() throws {
        let manager = ActivityManager()
        manager.register(
            RecordingActivity.started(.audio, at: Date(timeIntervalSince1970: 1))
        )

        let slot = try #require(compactSlots(for: manager.compactPresentation).first)

        #expect(slot.recordingSource == .audio)
        #expect(slot.symbolName == "mic.fill")
        #expect(AnimatedMicrophoneRecordingIcon.pulseCount == 3)
    }

    @Test("keeps microphone and screen recording visible at the same time")
    func concurrentRecordingSourcesUseSeparateSlots() {
        let manager = ActivityManager()
        manager.register(
            RecordingActivity.started(.audio, at: Date(timeIntervalSince1970: 1)),
            at: Date(timeIntervalSince1970: 1)
        )
        manager.register(
            RecordingActivity.started(.screen, at: Date(timeIntervalSince1970: 2)),
            at: Date(timeIntervalSince1970: 2)
        )

        let slots = compactSlots(for: manager.compactPresentation)

        #expect(slots.compactMap(\.recordingSource) == [.audio, .screen])
        #expect(Set(slots.map(\.id)).count == 2)
    }

    @Test("sizes the pill to the notch height and flanks its width")
    func pillHugsTheNotch() {
        let notch = CGSize(width: 200, height: 37)

        let size = compactPillSize(slotCount: 3, notchSize: notch)

        #expect(size.height == notch.height)
        #expect(size.width > notch.width)
    }

    // MARK: - Music icon visibility

    @Test("a paused note stays on the pill for twenty seconds")
    func pausedNoteDuration() {
        #expect(CompactMusicIconVisibility.pausedVisibleDuration == 20)
    }

    /// The user's rule: while music plays the icon never leaves.
    @Test("a playing track's icon never leaves the pill")
    func playingIconNeverLeaves() {
        var visibility = CompactMusicIconVisibility()

        visibility.advance(slots: [Self.musicSlot(.playing)], now: Self.t0)

        #expect(visibility.hiddenSlotIDs(at: Self.t0.addingTimeInterval(3_600)).isEmpty)
        #expect(visibility.nextDeadline(after: Self.t0) == nil)
    }

    @Test("a paused note leaves once its twenty seconds are up")
    func pausedNoteLeavesOnTime() {
        var visibility = CompactMusicIconVisibility()

        visibility.advance(slots: [Self.musicSlot(.paused)], now: Self.t0)

        #expect(visibility.hiddenSlotIDs(at: Self.t0.addingTimeInterval(19.9)).isEmpty)
        #expect(visibility.hiddenSlotIDs(at: Self.t0.addingTimeInterval(20)) == [MusicActivity.identity.rawValue])
    }

    /// New artwork or a skipped track while paused re-reports the pause; the
    /// countdown must not start over each time.
    @Test("a pause reported again keeps its original countdown")
    func repeatedPauseKeepsItsCountdown() {
        var visibility = CompactMusicIconVisibility()

        visibility.advance(slots: [Self.musicSlot(.paused)], now: Self.t0)
        visibility.advance(slots: [Self.musicSlot(.paused, title: "Nannou")], now: Self.t0.addingTimeInterval(10))

        #expect(visibility.hiddenSlotIDs(at: Self.t0.addingTimeInterval(20)) == [MusicActivity.identity.rawValue])
    }

    @Test("resuming brings the icon back, and the next pause counts from zero")
    func resumingRestoresTheIcon() {
        var visibility = CompactMusicIconVisibility()

        visibility.advance(slots: [Self.musicSlot(.paused)], now: Self.t0)
        visibility.advance(slots: [Self.musicSlot(.playing)], now: Self.t0.addingTimeInterval(30))
        #expect(visibility.hiddenSlotIDs(at: Self.t0.addingTimeInterval(30)).isEmpty)

        visibility.advance(slots: [Self.musicSlot(.paused)], now: Self.t0.addingTimeInterval(40))
        #expect(visibility.hiddenSlotIDs(at: Self.t0.addingTimeInterval(59)).isEmpty)
        #expect(visibility.hiddenSlotIDs(at: Self.t0.addingTimeInterval(60)) == [MusicActivity.identity.rawValue])
    }

    @Test("music that stops and returns paused counts from its return")
    func returningMusicCountsAfresh() {
        var visibility = CompactMusicIconVisibility()

        visibility.advance(slots: [Self.musicSlot(.paused)], now: Self.t0)
        visibility.advance(slots: [], now: Self.t0.addingTimeInterval(25))
        visibility.advance(slots: [Self.musicSlot(.paused)], now: Self.t0.addingTimeInterval(30))

        #expect(visibility.hiddenSlotIDs(at: Self.t0.addingTimeInterval(49)).isEmpty)
    }

    @Test("the next deadline is the paused note's departure, and nothing after it")
    func pausedNoteDeadline() {
        var visibility = CompactMusicIconVisibility()

        visibility.advance(slots: [Self.musicSlot(.paused)], now: Self.t0)

        #expect(visibility.nextDeadline(after: Self.t0) == Self.t0.addingTimeInterval(20))
        #expect(visibility.nextDeadline(after: Self.t0.addingTimeInterval(20)) == nil)
    }

    @Test("other kinds of slot never count down")
    func nonMusicSlotsNeverCountDown() {
        var visibility = CompactMusicIconVisibility()
        let timer = compactSlots(for: Self.workedExample().compactPresentation).filter { $0.id == "timer" }

        visibility.advance(slots: timer, now: Self.t0)

        #expect(visibility.nextDeadline(after: Self.t0) == nil)
    }

    // MARK: - Equaliser

    @Test("a playing track draws the animated equaliser")
    func equaliserAnimatesWhilePlaying() {
        #expect(
            Self.rendersEqualiserHost(playback: .playing, motionSuspended: false)
                == !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    @Test("the equaliser stands still while island motion is suspended")
    func equaliserStandsStillWhileSuspended() {
        #expect(Self.rendersEqualiserHost(playback: .playing, motionSuspended: true) == false)
    }

    @Test("a paused track draws the still note, not the equaliser")
    func pausedTrackDrawsNoEqualiser() {
        #expect(Self.rendersEqualiserHost(playback: .paused, motionSuspended: false) == false)
    }

    @Test("the equaliser bars stay centred at their resting heights")
    func equaliserBarsStayCentred() {
        let geometry = MusicEqualiserGeometry(symbolSize: 12)
        let frames = geometry.barFrames()

        #expect(frames.map(\.height) == MusicEqualiserGeometry.restingBarScales.map { $0 * 12 })
        #expect(frames.allSatisfy { abs($0.midY - 6) < 0.0001 })
        #expect(abs((frames.first?.minX ?? 0) - (12 - (frames.last?.maxX ?? 0))) < 0.0001)
    }

    private static let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    private static func musicSlot(_ playback: MusicPlaybackState, title: String = "Windowlicker") -> CompactSlot {
        musicCompactSlot(
            for: MusicActivity(
                nowPlaying: NowPlaying(
                    title: title,
                    artist: "Aphex Twin",
                    playbackState: playback,
                    sourceApplicationName: "Spotify"
                )
            )
        )
    }

    /// Whether the Core Animation equaliser host is in the rendered tree. The
    /// host is private to the module, so it is recognised by name, the same
    /// way the agent's working dot is.
    private static func rendersEqualiserHost(playback: MusicPlaybackState, motionSuspended: Bool) -> Bool {
        let manager = ActivityManager()
        manager.register(
            MusicActivity(
                nowPlaying: NowPlaying(
                    title: "Windowlicker",
                    artist: "Aphex Twin",
                    playbackState: playback,
                    sourceApplicationName: "Spotify"
                )
            )
        )
        let view = CompactActivityView(
            presentation: manager.compactPresentation,
            notchSize: CGSize(width: 200, height: 32)
        )
        .environment(\.islandMotionSuspended, motionSuspended)

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(x: 0, y: 0, width: 320, height: 40)
        hostingView.layoutSubtreeIfNeeded()
        return containsView(named: "MusicEqualiserHostView", in: hostingView)
    }

    private static func containsView(named name: String, in view: NSView) -> Bool {
        if String(describing: type(of: view)).contains(name) {
            return true
        }
        return view.subviews.contains { containsView(named: name, in: $0) }
    }

    /// The bug this split exists to prevent: the icon disappeared after its few
    /// seconds while the black bar behind it kept the width of the slot that was
    /// no longer drawn.
    @Test("hiding a music icon narrows the pill")
    func hidingMusicNarrowsThePill() throws {
        let manager = ActivityManager()
        manager.register(
            MusicActivity(
                nowPlaying: NowPlaying(
                    title: "Windowlicker",
                    artist: "Aphex Twin",
                    playbackState: .playing,
                    sourceApplicationName: "Spotify"
                )
            )
        )
        manager.register(Self.activity("timer", .timer, .high))
        let presentation = manager.compactPresentation
        let slots = compactSlots(for: presentation)
        let musicID = try #require(slots.first(where: { $0.musicSourceIdentity != nil })?.id)
        let notch = CGSize(width: 200, height: 32)

        let shown = compactPillSize(
            for: compactSlotLayout(for: presentation, hiding: []),
            notchSize: notch
        )
        let hidden = compactPillSize(
            for: compactSlotLayout(for: presentation, hiding: [musicID]),
            notchSize: notch
        )

        #expect(hidden.width < shown.width)
    }

    /// And the hover target has to shrink with it, or the pointer keeps
    /// reporting as over an island that has moved out from under it.
    @Test("hiding a music icon narrows the hover target")
    func hidingMusicNarrowsTheHitRect() throws {
        let manager = ActivityManager()
        manager.register(
            MusicActivity(
                nowPlaying: NowPlaying(
                    title: "Windowlicker",
                    artist: "Aphex Twin",
                    playbackState: .playing,
                    sourceApplicationName: "Spotify"
                )
            )
        )
        manager.register(Self.activity("timer", .timer, .high))
        let presentation = manager.compactPresentation
        let slots = compactSlots(for: presentation)
        let musicID = try #require(slots.first(where: { $0.musicSourceIdentity != nil })?.id)
        let screen = ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: ScreenSafeAreaInsets(top: 37),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 656, height: 37),
            auxiliaryTopRightArea: CGRect(x: 856, y: 945, width: 656, height: 37),
            isBuiltIn: true
        )

        func hitWidth(hiding hiddenIDs: Set<String>) -> CGFloat {
            let layout = compactSlotLayout(for: presentation, hiding: hiddenIDs)
            return compactHitRect(
                for: screen,
                leadingSlotCount: layout.leading.count,
                trailingSlotCount: layout.trailing.count
            ).width
        }

        #expect(hitWidth(hiding: [musicID]) < hitWidth(hiding: []))
    }

    private static func aiAgent(_ agent: IPCAgentID) -> AIAgentActivity {
        AIAgentActivity(
            agent: agent,
            sessionID: UUID(),
            state: .working,
            detail: "Working"
        )
    }
}
