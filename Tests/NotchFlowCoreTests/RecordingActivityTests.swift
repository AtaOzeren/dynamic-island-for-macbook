import Foundation
import Testing

@testable import NotchFlowCore

/// The recording indicator's value semantics: what it counts, what it promises
/// to the island's ordering, and what it deliberately refuses to claim. All of
/// it is pure logic over an injected date, so none of it needs a live capture
/// session or a granted permission.
@Suite("RecordingActivity")
struct RecordingActivityTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 0)

    private static func date(_ offset: TimeInterval) -> Date {
        start.addingTimeInterval(offset)
    }

    @Test("a fresh session reports its kind and a zero counter")
    func freshSession() {
        let recording = RecordingActivity.started(.screen, at: Self.start)

        #expect(recording.kind == .recording)
        #expect(recording.source == .screen)
        #expect(recording.elapsed == .zero)
    }

    /// Derived from the start timestamp, never accumulated — which is what lets
    /// the provider suspend the display refresh behind a hidden panel without
    /// the count drifting.
    @Test("derives elapsed time from the start timestamp rather than tick count")
    func elapsedFromTimestamps() {
        let recording = RecordingActivity.started(.screen, at: Self.start)

        #expect(recording.advanced(to: Self.date(1)).elapsed == .seconds(1))
        #expect(recording.advanced(to: Self.date(3600)).elapsed == .seconds(3600))
    }

    /// One late read is worth exactly as many on-time ones: advancing in one
    /// jump and advancing in steps land on the same value.
    @Test("advancing in steps matches advancing in one jump")
    func advancingIsPathIndependent() {
        let recording = RecordingActivity.started(.audio, at: Self.start)

        let stepped =
            recording
            .advanced(to: Self.date(10))
            .advanced(to: Self.date(20))
            .advanced(to: Self.date(30))

        #expect(stepped == recording.advanced(to: Self.date(30)))
    }

    /// A clock correction that moves backwards stalls the counter rather than
    /// running it negative.
    @Test("clamps a backwards clock to a stalled counter")
    func backwardsClockStalls() {
        let recording = RecordingActivity.started(.screen, at: Self.start)

        #expect(recording.advanced(to: Self.date(-30)).elapsed == .zero)
    }

    /// `docs/06-activity-providers.md`: an extra always-on indicator is the
    /// cheaper failure than silently missing a recording, so the indicator is
    /// high priority and never dismisses itself.
    @Test("stays high priority and never auto-dismisses")
    func priorityAndDismissal() {
        for source in [RecordingSource.screen, .audio] {
            let recording = RecordingActivity.started(source, at: Self.start)

            #expect(recording.priority == .high)
            #expect(recording.autoDismiss == nil)
        }
    }

    /// Screen and microphone captures are concurrent facts, so they must not
    /// share an identity — one would silently replace the other in the island.
    @Test("gives each source its own identity")
    func identityPerSource() {
        let screen = RecordingActivity.started(.screen, at: Self.start)
        let audio = RecordingActivity.started(.audio, at: Self.start)

        #expect(screen.identity != audio.identity)
    }

    /// Ticking must update the existing activity rather than register a new
    /// one, or the island re-sorts itself every second.
    @Test("keeps one identity across a tick")
    func identityIsStableAcrossTicks() {
        let recording = RecordingActivity.started(.screen, at: Self.start)

        #expect(recording.advanced(to: Self.date(60)).identity == recording.identity)
    }
}
