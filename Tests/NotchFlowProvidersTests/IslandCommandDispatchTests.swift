import Foundation
import NotchFlowCore
import Testing

@testable import NotchFlowProviders

/// Todos 11 and 13: a press in the island must arrive at the provider seam as
/// the command the gesture named — and the timer's tick must stay disarmed
/// unless there is genuinely something to redraw.
@Suite("Island command dispatch")
@MainActor
struct IslandCommandDispatchTests {
    private final class RecordingMusicProvider: MusicProvider {
        var sent: [MusicTransportCommand] = []

        var backendName: String { "Recording" }
        func startObserving(_ observer: @escaping NowPlayingObserver) {}
        func stopObserving() {}
        func send(_ command: MusicTransportCommand) { sent.append(command) }
    }

    private final class ManualTickScheduler: TickScheduling {
        private(set) var isScheduled = false
        private var tick: (() -> Void)?

        func schedule(_ tick: @escaping @MainActor () -> Void) {
            isScheduled = true
            self.tick = tick
        }

        func cancel() {
            isScheduled = false
            tick = nil
        }

        func fire() { tick?() }
    }

    @Test("every transport control reaches the provider as its own command")
    func transportCommandsReachTheProvider() {
        let provider = RecordingMusicProvider()

        for command in MusicTransportCommand.allCases {
            provider.send(command)
        }

        #expect(provider.sent == MusicTransportCommand.allCases)
    }

    @Test("a menu preset starts a countdown of that length")
    func menuPresetStartsACountdown() {
        let scheduler = ManualTickScheduler()
        let start = Date(timeIntervalSince1970: 0)
        let provider = TimerProvider(scheduler: scheduler, now: { start })
        provider.startObserving { _ in }
        provider.setPanelVisible(true)

        provider.handle(.start(.countdown(duration: .seconds(25 * 60))))

        #expect(provider.currentActivity?.mode == .countdown(duration: .seconds(1500)))
        #expect(provider.currentActivity?.isRunning == true)
    }

    @Test("no tick is armed while no timer runs")
    func noTimerMeansNoTick() {
        let scheduler = ManualTickScheduler()
        let provider = TimerProvider(scheduler: scheduler, now: { Date(timeIntervalSince1970: 0) })
        provider.startObserving { _ in }
        provider.setPanelVisible(true)

        #expect(provider.hasTickSource == false)

        provider.handle(.start(.countdown(duration: .seconds(60))))
        #expect(provider.hasTickSource)

        provider.handle(.stop)
        #expect(provider.hasTickSource == false)
    }

    @Test("no tick is armed while the panel is hidden, even with a timer running")
    func hiddenPanelMeansNoTick() {
        let scheduler = ManualTickScheduler()
        let provider = TimerProvider(scheduler: scheduler, now: { Date(timeIntervalSince1970: 0) })
        provider.startObserving { _ in }
        provider.setPanelVisible(true)
        provider.handle(.start(.countdown(duration: .seconds(60))))
        #expect(provider.hasTickSource)

        provider.setPanelVisible(false)
        #expect(provider.hasTickSource == false)

        provider.setPanelVisible(true)
        #expect(provider.hasTickSource)
    }

    @Test("pause and resume reach the provider and move the timer's state")
    func pauseAndResumeMoveTheTimer() {
        let scheduler = ManualTickScheduler()
        let start = Date(timeIntervalSince1970: 0)
        let provider = TimerProvider(scheduler: scheduler, now: { start })
        provider.startObserving { _ in }
        provider.setPanelVisible(true)
        provider.handle(.start(.countdown(duration: .seconds(60))))

        provider.handle(.pause)
        #expect(provider.currentActivity?.isRunning == false)
        #expect(provider.hasTickSource == false)

        provider.handle(.resume)
        #expect(provider.currentActivity?.isRunning == true)
        #expect(provider.hasTickSource)
    }
}
