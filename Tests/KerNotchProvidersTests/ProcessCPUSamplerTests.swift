import Darwin
import Dispatch
import Foundation
import KerNotchCore
import KerNotchProviders
import Testing

// MARK: - Fakes

/// Settable stand-in for the `clock_gettime` pair: one dial of process CPU
/// time, one dial of the suspending wall clock.
private final class FakeWatchdogClock: WatchdogClock {
    var processCPU: UInt64 = 0
    var uptime: UInt64 = 0

    var processCPUNanoseconds: UInt64 { processCPU }
    var uptimeNanoseconds: UInt64 { uptime }
}

/// Captures liveness pings instead of enqueueing them on the real main queue.
private final class FakeMainThreadExecutor: MainThreadPingExecuting {
    private(set) var blocks: [@Sendable () -> Void] = []

    func enqueueOnMainThread(_ block: @escaping @Sendable () -> Void) {
        blocks.append(block)
    }

    var pingCount: Int { blocks.count }

    /// Runs the newest ping's ack, as a healthy main thread would.
    func ackLatestPing() {
        blocks.last?()
    }
}

/// Thread-safe sink for samples delivered on the watchdog queue.
private final class SampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var percents: [Double] = []

    func record(_ sample: CPUSample) {
        lock.lock()
        defer { lock.unlock() }
        percents.append(sample.cpuPercent)
    }

    var maximumPercent: Double {
        lock.lock()
        defer { lock.unlock() }
        return percents.max() ?? 0
    }
}

// MARK: - 3.2 ProcessCPUSampler

@Suite("ProcessCPUSampler")
struct ProcessCPUSamplerTests {
    private func makeSampler() -> (
        sampler: ProcessCPUSampler, executor: FakeMainThreadExecutor, clock: FakeWatchdogClock
    ) {
        let clock = FakeWatchdogClock()
        let executor = FakeMainThreadExecutor()
        let probe = MainThreadLivenessProbe(executor: executor, clock: clock)
        return (ProcessCPUSampler(clock: clock, probe: probe), executor, clock)
    }

    /// A sampler whose cadence does not match the configuration's prunes each
    /// sample before the next arrives, so the degrade window never fills and
    /// the watchdog never fires — silently.
    @Test("the timer ticks at the configuration's own sample interval")
    func timerFollowsTheConfiguration() {
        let standard = ProcessCPUSampler(configuration: CPUWatchdog.Configuration())
        #expect(standard.interval == .nanoseconds(5_000_000_000))
        #expect(standard.leeway == .nanoseconds(1_000_000_000))

        let fast = ProcessCPUSampler(configuration: CPUWatchdog.Configuration(timeScale: 0.1))
        #expect(fast.interval == .nanoseconds(500_000_000))
        #expect(fast.leeway == .nanoseconds(100_000_000))
    }

    @Test("a duration becomes the nanosecond interval the timer takes")
    func durationConvertsToDispatchInterval() {
        #expect(ProcessCPUSampler.dispatchInterval(for: .seconds(5)) == .nanoseconds(5_000_000_000))
        #expect(ProcessCPUSampler.dispatchInterval(for: .milliseconds(500)) == .nanoseconds(500_000_000))
        #expect(ProcessCPUSampler.dispatchInterval(for: .zero) == .nanoseconds(0))
    }

    @Test("the first tick only establishes the baseline: no sample, no ping")
    func firstTickEmitsNothing() {
        let (sampler, executor, _) = makeSampler()

        #expect(sampler.takeSample() == nil)
        #expect(executor.pingCount == 0)
    }

    @Test("percent math is ΔCPU / ΔWall × 100, timestamped on the suspending clock")
    func percentMath() {
        let (sampler, _, clock) = makeSampler()

        #expect(sampler.takeSample() == nil)

        clock.processCPU = 250_000_000
        clock.uptime = 1_000_000_000
        let first = sampler.takeSample()

        clock.processCPU = 1_500_000_000
        clock.uptime = 2_000_000_000
        let second = sampler.takeSample()

        #expect(first?.cpuPercent == 25)
        #expect(second?.cpuPercent == 125)
        if let first, let second {
            #expect(second.at - first.at == .seconds(1))
        }
    }

    @Test("a multi-thread runaway passes through above 100%")
    func aboveHundredPassesThrough() {
        let (sampler, _, clock) = makeSampler()

        _ = sampler.takeSample()
        clock.processCPU = 1_500_000_000
        clock.uptime = 1_000_000_000

        #expect(sampler.takeSample()?.cpuPercent == 150)
    }

    @Test("zero elapsed wall time yields no sample and re-baselines")
    func zeroElapsedWallYieldsNothing() {
        let (sampler, _, clock) = makeSampler()

        #expect(sampler.takeSample() == nil)
        #expect(sampler.takeSample() == nil)

        clock.processCPU = 100_000_000
        clock.uptime = 500_000_000
        #expect(sampler.takeSample()?.cpuPercent == 20)
    }

    @Test("the sample carries main-thread responsiveness from the probe")
    func carriesResponsiveness() {
        let (sampler, executor, clock) = makeSampler()

        _ = sampler.takeSample()
        clock.processCPU = 100_000_000
        clock.uptime = 1_000_000_000
        _ = sampler.takeSample()
        executor.ackLatestPing()
        clock.processCPU += 100_000_000
        clock.uptime += 1_000_000_000
        let healthy = sampler.takeSample()
        #expect(healthy?.mainThreadResponsive == true)
        #expect(executor.pingCount == 2)

        clock.processCPU += 1_100_000_000
        clock.uptime += 11_000_000_000
        let hung = sampler.takeSample()
        #expect(hung?.mainThreadResponsive == false)
        #expect(executor.pingCount == 2)
    }

    // Integration test — real time, T9 exception: the unit bug it guards
    // (proc_pid_rusage reporting Mach absolute time as nanoseconds, reading
    // 2.4% for a 98% busy loop — plan, Review evidence) only reproduces
    // against the real system clock. Filter on "Integration" to exclude from
    // fast test runs.
    @Test("Integration: a 200 ms busy loop on a background thread samples above 50%")
    func busyLoopSamplesAboveFiftyPercent() async throws {
        let collector = SampleCollector()
        let sampler = ProcessCPUSampler(interval: .milliseconds(100), leeway: .milliseconds(10))
        defer { sampler.stop() }

        sampler.start { collector.record($0) }

        DispatchQueue.global(qos: .userInitiated).async {
            let started = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            while clock_gettime_nsec_np(CLOCK_UPTIME_RAW) &- started < 200_000_000 {}
        }

        let deadlineNanos = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) &+ 2_000_000_000
        while clock_gettime_nsec_np(CLOCK_UPTIME_RAW) < deadlineNanos {
            if collector.maximumPercent > 50 { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(collector.maximumPercent > 50)
    }
}

// MARK: - 3.3 MainThreadLivenessProbe

@Suite("MainThreadLivenessProbe")
struct MainThreadLivenessProbeTests {
    private func makeProbe() -> (
        probe: MainThreadLivenessProbe, executor: FakeMainThreadExecutor, clock: FakeWatchdogClock
    ) {
        let clock = FakeWatchdogClock()
        let executor = FakeMainThreadExecutor()
        return (MainThreadLivenessProbe(executor: executor, clock: clock), executor, clock)
    }

    @Test("an acked ping keeps the main thread responsive")
    func ackedPingIsResponsive() {
        let (probe, executor, clock) = makeProbe()
        clock.uptime = 100_000_000_000

        #expect(probe.tick() == true)
        #expect(executor.pingCount == 1)

        executor.ackLatestPing()
        clock.uptime += 1_000_000_000

        #expect(probe.tick() == true)
        #expect(executor.pingCount == 2)
    }

    @Test("a ping outstanding for ≥ 10 s of suspending time is unresponsive")
    func unacknowledgedPingTurnsUnresponsive() {
        let (probe, _, clock) = makeProbe()

        #expect(probe.tick() == true)
        clock.uptime = 5_000_000_000
        #expect(probe.tick() == true)
        clock.uptime = 10_000_000_000
        #expect(probe.tick() == false)
        clock.uptime = 15_000_000_000
        #expect(probe.tick() == false)
    }

    @Test("no second ping while one is outstanding")
    func neverRepingWhileOutstanding() {
        let (probe, executor, clock) = makeProbe()

        _ = probe.tick()
        clock.uptime = 5_000_000_000
        _ = probe.tick()
        clock.uptime = 10_000_000_000
        _ = probe.tick()
        clock.uptime = 15_000_000_000
        _ = probe.tick()

        #expect(executor.pingCount == 1)
    }

    @Test("a simulated sleep does not age the ping")
    func sleepDoesNotAgeThePing() {
        let (probe, executor, clock) = makeProbe()
        clock.uptime = 50_000_000_000

        _ = probe.tick()

        // 30 s of system sleep. CLOCK_UPTIME_RAW freezes while asleep, so the
        // uptime dial does not move; every other dial does. Advancing the CPU
        // dial alone models that divergence, so a probe reading the wrong dial
        // — or any wall-clock source — ages the ping past 10 s and calls a
        // healthy main thread hung. Decision 9 forbids exactly that.
        clock.processCPU += 30_000_000_000

        #expect(probe.tick() == true)
        #expect(executor.pingCount == 1)

        // After wake, ageing resumes from the pre-sleep instant: 9 s of
        // suspending time is still inside the 10 s budget even though 39 s of
        // wall time has passed since the ping went out.
        clock.uptime += 9_000_000_000

        #expect(probe.tick() == true)
        #expect(executor.pingCount == 1)

        // One more second crosses the budget on the suspending clock alone.
        clock.uptime += 1_000_000_000

        #expect(probe.tick() == false)
    }

    @Test("a late ack recovers responsiveness and allows a fresh ping")
    func lateAckRecovers() {
        let (probe, executor, clock) = makeProbe()

        _ = probe.tick()
        clock.uptime = 11_000_000_000
        #expect(probe.tick() == false)

        executor.ackLatestPing()
        clock.uptime += 1_000_000_000
        #expect(probe.tick() == true)
        #expect(executor.pingCount == 2)
    }
}
