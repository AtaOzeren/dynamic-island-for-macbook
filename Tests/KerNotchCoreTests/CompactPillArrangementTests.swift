import Foundation
import Testing

@testable import KerNotchCore

@Suite("Compact pill arrangement")
struct CompactPillArrangementTests {
    // MARK: - Rank

    @Test("ranks capture, call, notice, alert, transition, tracking, then ambient")
    func ranksFromMostToLeastImportant() {
        let shuffled: [CompactRank] = [.ambient, .notice, .tracking, .capture, .transition, .call, .alert]

        #expect(shuffled.sorted() == [.capture, .call, .notice, .alert, .transition, .tracking, .ambient])
    }

    @Test("every activity declares the rank the user's priority order gives it")
    func concreteActivitiesDeclareTheirRank() {
        let now = Date(timeIntervalSince1970: 0)

        #expect(RecordingActivity.started(.screen, at: now).compactRank == .capture)
        #expect(RecordingActivity.started(.audio, at: now).compactRank == .capture)
        #expect(DiscordCallActivity(channel: nil, isMuted: nil).compactRank == .call)
        #expect(WatchdogNoticeActivity(didRelaunch: true).compactRank == .notice)
        #expect(ChargingActivity(state: .charging, level: BatteryLevel(fraction: 0.5)).compactRank == .transition)
        #expect(
            MusicActivity(
                nowPlaying: NowPlaying(title: "Windowlicker", artist: "Aphex Twin", playbackState: .playing)
            ).compactRank == .ambient
        )
    }

    @Test("a countdown outranks the charger only once it has expired")
    func expiredTimerIsAnAlert() {
        let start = Date(timeIntervalSince1970: 0)
        let running = TimerActivity.started(.countdown(duration: .seconds(60)), at: start)

        #expect(running.compactRank == .tracking)
        #expect(running.advanced(to: start.addingTimeInterval(60)).compactRank == .alert)
        #expect(TimerActivity.started(.stopwatch, at: start).compactRank == .tracking)
    }

    // MARK: - Flank allocation

    @Test(
        "without agents, the leading side fills first and holds the odd icon",
        arguments: [
            (0, 0, 0),
            (1, 1, 0),
            (2, 1, 1),
            (3, 2, 1),
            (4, 2, 2),
            (5, 2, 2),
            (9, 2, 2),
        ]
    )
    func allocationWithoutAgents(standard: Int, leading: Int, trailing: Int) {
        let allocation = CompactFlankAllocation(standardCount: standard, agentCount: 0)

        #expect(allocation.leadingStandardCount == leading)
        #expect(allocation.trailingStandardCount == trailing)
    }

    @Test(
        "with agents, standard icons keep to the leading side",
        arguments: [
            (0, 1, 0),
            (1, 1, 1),
            (2, 2, 2),
            (3, 3, 2),
            (5, 1, 2),
        ]
    )
    func allocationWithAgents(standard: Int, agents: Int, leading: Int) {
        let allocation = CompactFlankAllocation(standardCount: standard, agentCount: agents)

        #expect(allocation.leadingStandardCount == leading)
        #expect(allocation.trailingStandardCount == 0)
    }

    @Test("a negative count allocates nothing")
    func negativeCountsAllocateNothing() {
        let allocation = CompactFlankAllocation(standardCount: -1, agentCount: -1)

        #expect(allocation.leadingStandardCount == 0)
        #expect(allocation.trailingStandardCount == 0)
    }
}
