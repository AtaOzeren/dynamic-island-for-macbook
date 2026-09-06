import Darwin
import Dispatch
import Foundation

import NotchFlowCore

// MARK: - Clock pair

/// The two dials the CPU watchdog reads, in nanoseconds.
///
/// A pair, not one clock read twice: process CPU time and the suspending wall
/// clock advance differently, and their quotient is the CPU percent.
public protocol WatchdogClock: AnyObject {
    /// `clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)`: CPU time consumed by
    /// the whole process. Never `proc_pid_rusage` for this — its time fields
    /// are Mach absolute time units, which read 2.4% for a 98% busy loop on
    /// this Mac (plan, Review evidence row 1).
    var processCPUNanoseconds: UInt64 { get }

    /// `clock_gettime_nsec_np(CLOCK_UPTIME_RAW)`: nanoseconds since boot,
    /// frozen while the system sleeps. Decision 9: every watchdog duration —
    /// sample windows and the liveness ping age — is measured here, so a
    /// system sleep neither dilutes a sample nor ages a ping into a false
    /// "hung main thread".
    var uptimeNanoseconds: UInt64 { get }
}

/// The production clock: one `clock_gettime` call per dial read.
public final class SystemWatchdogClock: WatchdogClock, Sendable {
    public init() {}

    public var processCPUNanoseconds: UInt64 {
        clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
    }

    public var uptimeNanoseconds: UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }
}

// MARK: - Main-thread liveness probe

/// Where a liveness ping's ack block is enqueued; injectable so tests capture
/// the block instead of touching the real main queue.
public protocol MainThreadPingExecuting: AnyObject {
    func enqueueOnMainThread(_ block: @escaping @Sendable () -> Void)
}

/// The production executor: `DispatchQueue.main.async`.
public final class DispatchMainPingExecutor: MainThreadPingExecuting, Sendable {
    public init() {}

    public func enqueueOnMainThread(_ block: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async(execute: block)
    }
}

/// Reports whether the main thread is still serving blocks, by pinging it.
///
/// Semantics (plan, Task 2.2): a ping is a block enqueued on the main queue
/// whose execution is the ack; a ping outstanding for ≥ 10 s of suspending
/// time means unresponsive; a second ping is never sent while one is
/// outstanding. The ping ages on `CLOCK_UPTIME_RAW` (decision 9), so a system
/// sleep never reads as a hung main thread — the suspending clock is frozen
/// while asleep, leaving a ping sent just before sleep young after wake.
public final class MainThreadLivenessProbe: @unchecked Sendable {
    /// A ping this old, in suspending-clock nanoseconds, means unresponsive.
    public static let unresponsiveAfterNanoseconds: UInt64 = 10_000_000_000

    private let executor: MainThreadPingExecuting
    private let clock: WatchdogClock
    private let lock = NSLock()
    /// Send instant of the outstanding ping on the suspending clock; `nil`
    /// when no ping is in flight — never sent, or acked.
    private var pingSentAtNanoseconds: UInt64?

    public init(
        executor: MainThreadPingExecuting = DispatchMainPingExecutor(),
        clock: WatchdogClock = SystemWatchdogClock()
    ) {
        self.executor = executor
        self.clock = clock
    }

    /// One watchdog tick: reports whether the main thread is responsive right
    /// now, then sends a fresh ping if none is outstanding.
    public func tick() -> Bool {
        let now = clock.uptimeNanoseconds
        var responsive = true
        var shouldSendPing = false

        lock.lock()
        if let sentAt = pingSentAtNanoseconds {
            responsive = now &- sentAt < Self.unresponsiveAfterNanoseconds
        } else {
            shouldSendPing = true
            pingSentAtNanoseconds = now
        }
        lock.unlock()

        // Enqueue outside the lock: an executor that runs the block inline
        // would otherwise deadlock on the ack's lock acquisition.
        if shouldSendPing {
            executor.enqueueOnMainThread { [weak self] in
                self?.acknowledgePing()
            }
        }
        return responsive
    }

    private func acknowledgePing() {
        lock.lock()
        pingSentAtNanoseconds = nil
        lock.unlock()
    }
}

// MARK: - Sampler

/// What the sampler delivers each interval. The callback runs on the watchdog
/// queue; this is the exact signature the supervisor (Task 2.4) provides.
public typealias CPUSampleHandler = @Sendable (CPUSample) -> Void

/// Samples the process's own CPU use and main-thread liveness on a single
/// low-cost tick, and hands every `CPUSample` to the callback.
///
/// Cost per tick: one `clock_gettime` pair plus one main-queue block enqueue —
/// well inside the < 1 wakeup/s budget in `docs/02-performance-contract.md`.
/// Everything runs on the watchdog queue (label `com.notchflow.cpu-watchdog`,
/// utility QoS), per the plan's DispatchSourceTimer configuration: 5 s
/// interval, 1 s leeway.
public final class ProcessCPUSampler: @unchecked Sendable {
    public static let standardInterval: DispatchTimeInterval = .seconds(5)
    public static let standardLeeway: DispatchTimeInterval = .seconds(1)

    private let clock: WatchdogClock
    private let probe: MainThreadLivenessProbe
    public let interval: DispatchTimeInterval
    public let leeway: DispatchTimeInterval
    private let watchdogQueue = DispatchQueue(label: "com.notchflow.cpu-watchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastCPUNanoseconds: UInt64?
    private var lastWallNanoseconds: UInt64?

    /// Anchors the `ContinuousClock.Instant` timeline every sample's `at`
    /// lives on: sample instants differ from this by exactly the
    /// `CLOCK_UPTIME_RAW` delta, so the pure watchdog's window math stays
    /// sleep-proof (decision 9) while using the instant type Task 2.1's
    /// `CPUSample` already carries.
    private let instantAnchor: ContinuousClock.Instant
    private let uptimeAnchorNanoseconds: UInt64

    public init(
        clock: WatchdogClock = SystemWatchdogClock(),
        probe: MainThreadLivenessProbe? = nil,
        interval: DispatchTimeInterval = ProcessCPUSampler.standardInterval,
        leeway: DispatchTimeInterval = ProcessCPUSampler.standardLeeway
    ) {
        self.clock = clock
        self.probe = probe ?? MainThreadLivenessProbe(executor: DispatchMainPingExecutor(), clock: clock)
        self.interval = interval
        self.leeway = leeway
        self.instantAnchor = ContinuousClock().now
        self.uptimeAnchorNanoseconds = clock.uptimeNanoseconds
    }

    /// Ticks at the cadence the state machine counts in.
    ///
    /// The windows are counted in *samples* and pruned by *time*, so the two
    /// cadences have to be the same number: a sampler left at 5 s under a
    /// configuration scaled to a 3 s degrade window prunes each sample before
    /// the next arrives, and the window never fills at all. Deriving the timer
    /// from the configuration is what makes `--cpu-drill-fast-clock` reach the
    /// long-horizon thresholds instead of silently disarming the watchdog.
    public convenience init(
        configuration: CPUWatchdog.Configuration,
        clock: WatchdogClock = SystemWatchdogClock(),
        probe: MainThreadLivenessProbe? = nil
    ) {
        self.init(
            clock: clock,
            probe: probe,
            interval: Self.dispatchInterval(for: configuration.sampleInterval),
            // The stock 5 s / 1 s ratio, kept under any scale: leeway is what
            // lets the timer coalesce with other wakeups, and the performance
            // contract in `docs/02-performance-contract.md` counts on it.
            leeway: Self.dispatchInterval(for: configuration.sampleInterval / 5)
        )
    }

    /// A `Duration` as the nanosecond interval `DispatchSourceTimer` takes.
    public static func dispatchInterval(for duration: Duration) -> DispatchTimeInterval {
        let parts = duration.components
        return .nanoseconds(
            Int(clamping: parts.seconds * 1_000_000_000 + parts.attoseconds / 1_000_000_000)
        )
    }

    /// The watchdog timeline as an instant, for wiring the pure watchdog's
    /// `now:` closure so its windows and the samples it feeds on share one
    /// sleep-proof clock (Task 2.4).
    public var now: ContinuousClock.Instant {
        instantAnchor.advanced(by: .nanoseconds(Int64(clamping: clock.uptimeNanoseconds &- uptimeAnchorNanoseconds)))
    }

    /// Arms the tick. `onSample` runs on the watchdog queue once per interval;
    /// the first tick only establishes the baseline and delivers nothing.
    public func start(onSample: @escaping CPUSampleHandler) {
        watchdogQueue.sync {
            timer?.setEventHandler(handler: nil)
            timer?.cancel()

            let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
            timer.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
            timer.setEventHandler { [weak self] in
                guard let sample = self?.sampleOnQueue() else { return }
                onSample(sample)
            }
            timer.resume()
            self.timer = timer
        }
    }

    public func stop() {
        watchdogQueue.sync {
            timer?.setEventHandler(handler: nil)
            timer?.cancel()
            timer = nil
        }
    }

    /// Takes one sample from the caller's thread — the same path a timer tick
    /// takes — so the percent math is testable without waiting. Must not be
    /// called from `onSample` (that already runs on the watchdog queue).
    public func takeSample() -> CPUSample? {
        dispatchPrecondition(condition: .notOnQueue(watchdogQueue))
        return watchdogQueue.sync { sampleOnQueue() }
    }

    private func sampleOnQueue() -> CPUSample? {
        let cpuNow = clock.processCPUNanoseconds
        let wallNow = clock.uptimeNanoseconds
        defer {
            lastCPUNanoseconds = cpuNow
            lastWallNanoseconds = wallNow
        }

        guard let lastCPU = lastCPUNanoseconds, let lastWall = lastWallNanoseconds else {
            return nil
        }
        let elapsedWall = wallNow &- lastWall
        guard elapsedWall > 0 else { return nil }

        let elapsedCPU = cpuNow &- lastCPU
        return CPUSample(
            cpuPercent: Double(elapsedCPU) / Double(elapsedWall) * 100,
            mainThreadResponsive: probe.tick(),
            at: instantAnchor.advanced(by: .nanoseconds(Int64(clamping: wallNow &- uptimeAnchorNanoseconds)))
        )
    }

    deinit {
        timer?.cancel()
    }
}
