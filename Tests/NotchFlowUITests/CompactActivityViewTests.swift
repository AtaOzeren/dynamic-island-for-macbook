import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

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

    @Test("music compact icon announcement lasts five seconds")
    func musicIconAnnouncementDuration() {
        #expect(CompactMusicIconVisibility.visibleDuration == .seconds(5))
    }

    @Test("music icon hides after its announcement and returns for a later session")
    func musicIconVisibilityLifecycle() throws {
        let manager = ActivityManager()
        let music = MusicActivity(
            nowPlaying: NowPlaying(
                title: "Windowlicker",
                artist: "Aphex Twin",
                playbackState: .playing,
                sourceApplicationName: "Spotify"
            )
        )
        manager.register(music)
        manager.register(Self.activity("timer", .timer, .high))
        let slots = compactSlots(for: manager.compactPresentation)
        let musicID = try #require(slots.first(where: { $0.musicSourceIdentity != nil })?.id)
        var visibility = CompactMusicIconVisibility()
        var hidden: Set<String> = []

        #expect(
            visibility.synchronize(activeSlots: slots, hiddenSlotIDs: &hidden) == [musicID]
        )
        #expect(
            visibility.synchronize(activeSlots: slots, hiddenSlotIDs: &hidden).isEmpty
        )

        #expect(visibility.hasAnnounced(musicID))
        hidden.insert(musicID)

        #expect(visibleCompactSlots(slots, hiding: hidden).allSatisfy { $0.id != musicID })
        #expect(visibleCompactSlots(slots, hiding: hidden).contains { $0.id == "timer" })

        // A slot that goes away is forgotten, so the icon announces itself again
        // when the same track comes back.
        #expect(visibility.synchronize(activeSlots: [], hiddenSlotIDs: &hidden).isEmpty)
        #expect(hidden.isEmpty, "a departed slot must not stay in the hidden set")
        #expect(
            visibility.synchronize(activeSlots: slots, hiddenSlotIDs: &hidden) == [musicID]
        )
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
