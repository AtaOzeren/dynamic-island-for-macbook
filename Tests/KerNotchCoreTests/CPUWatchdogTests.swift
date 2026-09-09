import Testing

@testable import KerNotchCore

@Suite("CPUWatchdog")
struct CPUWatchdogTests {
    private final class Clock: @unchecked Sendable {
        private(set) var now = ContinuousClock().now

        func advance(by duration: Duration) {
            now = now.advanced(by: duration)
        }
    }

    private final class FakeRestartLedger: RestartLedger, @unchecked Sendable {
        private var restartDates: [ContinuousClock.Instant] = []

        func recordRestart(at date: ContinuousClock.Instant) {
            restartDates.append(date)
        }

        func restarts(since date: ContinuousClock.Instant) -> Int {
            restartDates.count { $0 >= date }
        }
    }

    private struct Fixture {
        let clock: Clock
        let ledger: FakeRestartLedger
        let watchdog: CPUWatchdog

        init(configuration: CPUWatchdog.Configuration = .init()) {
            let clock = Clock()
            let ledger = FakeRestartLedger()
            self.clock = clock
            self.ledger = ledger
            watchdog = CPUWatchdog(
                configuration: configuration,
                restartLedger: ledger,
                now: { clock.now }
            )
        }

        @discardableResult
        func feed(
            _ cpuPercent: Double,
            responsive: Bool = true,
            after duration: Duration = .seconds(5)
        ) -> CPUWatchdog.Action? {
            clock.advance(by: duration)
            return watchdog.feed(
                CPUSample(
                    cpuPercent: cpuPercent,
                    mainThreadResponsive: responsive,
                    at: clock.now
                )
            )
        }

        func finishWarmUp() {
            #expect(feed(100, after: .seconds(60)) == nil)
        }

        @discardableResult
        func enterDegradedMode(
            interval: Duration = .seconds(5),
            cpuPercent: Double = 25
        ) -> CPUWatchdog.Action? {
            var action: CPUWatchdog.Action?
            for _ in 0..<6 {
                action = feed(cpuPercent, after: interval)
            }
            return action
        }

        func degradedDwell() -> Duration? {
            guard case let .degraded(_, dwell) = watchdog.state else { return nil }
            return dwell
        }
    }

    @Test("Samples during the 60 s grace are ignored")
    func samplesDuringGraceAreIgnored() {
        let fixture = Fixture()

        for _ in 0..<11 {
            #expect(fixture.feed(100) == nil)
        }
        #expect(fixture.feed(100) == nil)
        for _ in 0..<5 {
            #expect(fixture.feed(100) == nil)
        }
        #expect(fixture.feed(100) == .degrade)
    }

    @Test("Noise below threshold never degrades")
    func noiseBelowThresholdNeverDegrades() {
        let fixture = Fixture()
        fixture.finishWarmUp()

        for cpuPercent in [3.0, 19.0, 7.0, 19.9, 2.0, 18.0, 10.0, 0.0] {
            #expect(fixture.feed(cpuPercent) == nil)
        }
        #expect(fixture.watchdog.state == .normal)
    }

    @Test("5-of-6 window: one 19% sample does not reset; window not evaluated until full")
    func fiveOfSixWindow() {
        let fixture = Fixture()
        fixture.finishWarmUp()
        let samples = [25.0, 25.0, 19.0, 25.0, 25.0]

        for cpuPercent in samples {
            #expect(fixture.feed(cpuPercent) == nil)
        }
        #expect(fixture.feed(25) == .degrade)
    }

    @Test("Exactly-30 s boundary")
    func exactlyThirtySecondBoundary() {
        let fixture = Fixture()
        fixture.finishWarmUp()

        for _ in 0..<5 {
            #expect(fixture.feed(25) == nil)
        }
        #expect(fixture.feed(25) == .degrade)
    }

    @Test("degrade → restore blocked before dwell, allowed after")
    func restoreRespectsMinimumDwell() {
        let fixture = Fixture()
        fixture.finishWarmUp()
        #expect(fixture.enterDegradedMode() == .degrade)

        for _ in 0..<6 {
            #expect(fixture.feed(15) == nil)
        }
        fixture.clock.advance(by: .seconds(240))
        for _ in 0..<5 {
            #expect(fixture.feed(15) == nil)
        }
        #expect(fixture.feed(15) == .restore)
    }

    @Test("restore needs all 6 ≤ 20% (one 21% blocks it)")
    func restoreRequiresEveryRecoverySample() {
        let fixture = Fixture()
        fixture.finishWarmUp()
        #expect(fixture.enterDegradedMode(cpuPercent: 21) == .degrade)
        fixture.clock.advance(by: .seconds(270))

        for cpuPercent in [15.0, 15.0, 21.0, 15.0, 15.0, 15.0] {
            #expect(fixture.feed(cpuPercent) == nil)
        }
        for _ in 0..<2 {
            #expect(fixture.feed(15) == nil)
        }
        #expect(fixture.feed(15) == .restore)
    }

    @Test("Dwell doubling within 1 h, cap 60 min, reset after 1 h clean")
    func degradedDwellDoublesCapsAndResets() {
        let configuration = CPUWatchdog.Configuration(
            minimumDegradedDwell: .seconds(5),
            maximumDwell: .seconds(60)
        )
        let fixture = Fixture(configuration: configuration)
        fixture.finishWarmUp()

        for expectedDwell in [5, 10, 20, 40, 60, 60] {
            #expect(fixture.enterDegradedMode() == .degrade)
            #expect(fixture.degradedDwell() == .seconds(expectedDwell))
            fixture.clock.advance(by: .seconds(expectedDwell - 30))
            for _ in 0..<6 {
                _ = fixture.feed(15)
            }
            #expect(fixture.watchdog.state == .normal)
        }

        fixture.clock.advance(by: .seconds(3601))
        #expect(fixture.enterDegradedMode(cpuPercent: 21) == .degrade)
        #expect(fixture.degradedDwell() == .seconds(5))
        #expect(CPUWatchdog.Configuration().maximumDwell == .seconds(3600))
    }

    @Test("degrade → one 41% sample → still degraded")
    func oneAlarmLevelSampleStaysDegraded() {
        let fixture = Fixture()
        fixture.finishWarmUp()
        #expect(fixture.enterDegradedMode() == .degrade)

        #expect(fixture.feed(41) == nil)
        #expect(fixture.degradedDwell() != nil)
    }

    @Test("41%, 41% → .alarmAndRestart(.cpuAboveAlarmThreshold)")
    func consecutiveAlarmLevelSamplesRestart() {
        let fixture = Fixture()
        fixture.finishWarmUp()
        #expect(fixture.enterDegradedMode() == .degrade)

        #expect(fixture.feed(41) == nil)
        #expect(fixture.feed(41) == .alarmAndRestart(reason: .cpuAboveAlarmThreshold))
    }

    @Test("41%, 39%, 41% → still degraded")
    func interruptedAlarmLevelSamplesStayDegraded() {
        let fixture = Fixture()
        fixture.finishWarmUp()
        #expect(fixture.enterDegradedMode(cpuPercent: 21) == .degrade)

        for cpuPercent in [41.0, 39.0, 41.0] {
            #expect(fixture.feed(cpuPercent) == nil)
        }
        #expect(fixture.degradedDwell() != nil)
    }

    @Test("degraded 15 min at 25% → .alarmAndRestart(.degradeFailed)")
    func sustainedDegradedCPUTriggersRestart() {
        let fixture = Fixture()
        fixture.finishWarmUp()
        #expect(fixture.enterDegradedMode() == .degrade)

        for _ in 0..<179 {
            #expect(fixture.feed(25) == nil)
        }
        #expect(fixture.feed(25) == .alarmAndRestart(reason: .degradeFailed))
    }

    @Test("degraded 15 min at 15% → no alarm (degrade rule no longer holds)")
    func recoveredCPUDoesNotTriggerDegradeFailure() {
        let configuration = CPUWatchdog.Configuration(minimumDegradedDwell: .seconds(1200))
        let fixture = Fixture(configuration: configuration)
        fixture.finishWarmUp()
        #expect(fixture.enterDegradedMode() == .degrade)

        for _ in 0..<180 {
            #expect(fixture.feed(15) == nil)
        }
        #expect(fixture.degradedDwell() != nil)
    }

    @Test("main unresponsive ×2 with > 20% → alarm directly from normal with .mainThreadUnresponsive")
    func unresponsiveMainThreadWithElevatedCPUAlarms() {
        let fixture = Fixture()
        fixture.finishWarmUp()

        #expect(fixture.feed(25, responsive: false) == nil)
        #expect(
            fixture.feed(25, responsive: false)
                == .alarmAndRestart(reason: .mainThreadUnresponsive)
        )
    }

    @Test("main unresponsive ×2 at 5% → nothing (CPU not above threshold)")
    func unresponsiveMainThreadAtLowCPUDoesNothing() {
        let fixture = Fixture()
        fixture.finishWarmUp()

        #expect(fixture.feed(5, responsive: false) == nil)
        #expect(fixture.feed(5, responsive: false) == nil)
        #expect(fixture.watchdog.state == .normal)
    }

    @Test("ledger at 3 within 1 h → .alarmAndQuit")
    func restartLoopQuits() {
        let fixture = Fixture()
        for _ in 0..<3 {
            fixture.ledger.recordRestart(at: fixture.clock.now)
        }
        fixture.finishWarmUp()

        #expect(fixture.feed(25, responsive: false) == nil)
        #expect(fixture.feed(25, responsive: false) == .alarmAndQuit(reason: .mainThreadUnresponsive))
    }

    @Test("ledger at 3 spread over 2 h → .alarmAndRestart")
    func restartsOutsideWindowDoNotQuit() {
        let fixture = Fixture()
        fixture.ledger.recordRestart(at: fixture.clock.now.advanced(by: .zero - .seconds(7200)))
        fixture.ledger.recordRestart(at: fixture.clock.now.advanced(by: .zero - .seconds(4000)))
        fixture.ledger.recordRestart(at: fixture.clock.now.advanced(by: .zero - .seconds(100)))
        fixture.finishWarmUp()

        #expect(fixture.feed(25, responsive: false) == nil)
        #expect(
            fixture.feed(25, responsive: false)
                == .alarmAndRestart(reason: .mainThreadUnresponsive)
        )
    }

    @Test("one .degrade per episode (second call to feed in same episode does not re-emit)")
    func degradeEmitsOncePerEpisode() {
        let fixture = Fixture()
        fixture.finishWarmUp()

        #expect(fixture.enterDegradedMode() == .degrade)
        #expect(fixture.feed(25) == nil)
        #expect(fixture.feed(25) == nil)
    }

    @Test("timeScale = 0.1 scales every duration")
    func timeScaleScalesEveryDuration() {
        let configuration = CPUWatchdog.Configuration(timeScale: 0.1)
        #expect(configuration.sampleInterval == .milliseconds(500))
        #expect(configuration.startupGracePeriod == .seconds(6))
        #expect(configuration.degradeWindow == .seconds(3))
        #expect(configuration.recoveryWindow == .seconds(3))
        #expect(configuration.minimumDegradedDwell == .seconds(30))
        #expect(configuration.dwellDoublingHorizon == .seconds(360))
        #expect(configuration.maximumDwell == .seconds(360))
        #expect(configuration.degradeFailureTimeout == .seconds(90))
        #expect(configuration.restartLoopWindow == .seconds(360))

        let fixture = Fixture(configuration: configuration)
        #expect(fixture.feed(100, after: .seconds(5.9)) == nil)
        #expect(fixture.feed(100, after: .seconds(0.1)) == nil)
        for _ in 0..<5 {
            #expect(fixture.feed(25, after: .milliseconds(500)) == nil)
        }
        #expect(fixture.feed(25, after: .milliseconds(500)) == .degrade)
        #expect(fixture.degradedDwell() == .seconds(30))
    }
}
