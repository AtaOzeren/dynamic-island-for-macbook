public struct CPUSample: Sendable {
    public let cpuPercent: Double
    public let mainThreadResponsive: Bool
    public let at: ContinuousClock.Instant

    public init(
        cpuPercent: Double,
        mainThreadResponsive: Bool,
        at: ContinuousClock.Instant
    ) {
        self.cpuPercent = cpuPercent
        self.mainThreadResponsive = mainThreadResponsive
        self.at = at
    }
}

public protocol RestartLedger: AnyObject {
    func recordRestart(at date: ContinuousClock.Instant)
    func restarts(since date: ContinuousClock.Instant) -> Int
}

public final class CPUWatchdog {
    /// Watchdog policy from `docs/02-performance-contract.md` and Decisions 1–9
    /// in `.omo/plans/2026-09-06-cpu-runaway-fixes-and-watchdog.md`.
    /// `timeScale` is applied once during construction to every duration.
    public struct Configuration: Sendable {
        public var sampleInterval: Duration
        public var startupGracePeriod: Duration
        public var degradeThresholdPercent: Double
        public var degradeWindow: Duration
        public var degradeWindowMinimumHits: Int
        public var recoveryWindow: Duration
        public var recoveryWindowRequiredHits: Int
        public var minimumDegradedDwell: Duration
        public var dwellDoublingHorizon: Duration
        public var maximumDwell: Duration
        public var alarmThresholdPercent: Double
        public var alarmConsecutiveSamples: Int
        public var degradeFailureTimeout: Duration
        public var mainThreadUnresponsiveSamplesBeforeAlarm: Int
        public var restartLoopLimit: Int
        public var restartLoopWindow: Duration
        public var timeScale: Double

        public init(
            sampleInterval: Duration = .seconds(5),
            startupGracePeriod: Duration = .seconds(60),
            degradeThresholdPercent: Double = 20,
            degradeWindow: Duration = .seconds(30),
            degradeWindowMinimumHits: Int = 5,
            recoveryWindow: Duration = .seconds(30),
            recoveryWindowRequiredHits: Int = 6,
            minimumDegradedDwell: Duration = .seconds(300),
            dwellDoublingHorizon: Duration = .seconds(3600),
            maximumDwell: Duration = .seconds(3600),
            alarmThresholdPercent: Double = 40,
            alarmConsecutiveSamples: Int = 2,
            degradeFailureTimeout: Duration = .seconds(900),
            mainThreadUnresponsiveSamplesBeforeAlarm: Int = 2,
            restartLoopLimit: Int = 3,
            restartLoopWindow: Duration = .seconds(3600),
            timeScale: Double = 1.0
        ) {
            self.sampleInterval = sampleInterval * timeScale
            self.startupGracePeriod = startupGracePeriod * timeScale
            self.degradeThresholdPercent = degradeThresholdPercent
            self.degradeWindow = degradeWindow * timeScale
            self.degradeWindowMinimumHits = degradeWindowMinimumHits
            self.recoveryWindow = recoveryWindow * timeScale
            self.recoveryWindowRequiredHits = recoveryWindowRequiredHits
            self.minimumDegradedDwell = minimumDegradedDwell * timeScale
            self.dwellDoublingHorizon = dwellDoublingHorizon * timeScale
            self.maximumDwell = maximumDwell * timeScale
            self.alarmThresholdPercent = alarmThresholdPercent
            self.alarmConsecutiveSamples = alarmConsecutiveSamples
            self.degradeFailureTimeout = degradeFailureTimeout * timeScale
            self.mainThreadUnresponsiveSamplesBeforeAlarm = mainThreadUnresponsiveSamplesBeforeAlarm
            self.restartLoopLimit = restartLoopLimit
            self.restartLoopWindow = restartLoopWindow * timeScale
            self.timeScale = timeScale
        }
    }

    public enum State: Equatable, Sendable {
        case warmingUp
        case normal
        case degraded(since: ContinuousClock.Instant, dwell: Duration)
        case alarmed
    }

    public enum Action: Equatable, Sendable {
        case degrade
        case restore
        case alarmAndRestart(reason: AlarmReason)
        case alarmAndQuit(reason: AlarmReason)
    }

    public enum AlarmReason: Equatable, Sendable {
        case cpuAboveAlarmThreshold
        case mainThreadUnresponsive
        case degradeFailed
    }

    private(set) var state: State = .warmingUp

    private let configuration: Configuration
    private let restartLedger: any RestartLedger
    private let startedAt: ContinuousClock.Instant
    private var samples: [CPUSample] = []
    private var degradedEpisodeStarts: [ContinuousClock.Instant] = []
    private var consecutiveAlarmSamples = 0
    private var consecutiveUnresponsiveSamples = 0

    public init(
        configuration: Configuration = .init(),
        restartLedger: any RestartLedger,
        now: () -> ContinuousClock.Instant = { ContinuousClock().now }
    ) {
        self.configuration = configuration
        self.restartLedger = restartLedger
        startedAt = now()
    }

    public func feed(_ sample: CPUSample) -> Action? {
        switch state {
        case .warmingUp:
            return feedDuringWarmUp(sample)
        case .normal:
            return feedWhileNormal(sample)
        case let .degraded(since, dwell):
            return feedWhileDegraded(sample, since: since, dwell: dwell)
        case .alarmed:
            return nil
        }
    }

    private func feedDuringWarmUp(_ sample: CPUSample) -> Action? {
        guard startedAt.duration(to: sample.at) >= configuration.startupGracePeriod else {
            return nil
        }
        state = .normal
        resetCurrentEpisodeSamples()
        return nil
    }

    private func feedWhileNormal(_ sample: CPUSample) -> Action? {
        append(sample)
        updateConsecutiveSampleCounts(with: sample)

        if shouldAlarmForUnresponsiveMainThread(latestCPUPercent: sample.cpuPercent) {
            return alarm(reason: .mainThreadUnresponsive, at: sample.at)
        }
        guard degradeRuleHolds() else { return nil }

        let dwell = dwellForEpisode(startingAt: sample.at)
        degradedEpisodeStarts.append(sample.at)
        state = .degraded(since: sample.at, dwell: dwell)
        consecutiveAlarmSamples = 0
        return .degrade
    }

    private func feedWhileDegraded(
        _ sample: CPUSample,
        since: ContinuousClock.Instant,
        dwell: Duration
    ) -> Action? {
        append(sample)
        updateConsecutiveSampleCounts(with: sample)

        if consecutiveAlarmSamples >= configuration.alarmConsecutiveSamples {
            return alarm(reason: .cpuAboveAlarmThreshold, at: sample.at)
        }
        if shouldAlarmForUnresponsiveMainThread(latestCPUPercent: sample.cpuPercent) {
            return alarm(reason: .mainThreadUnresponsive, at: sample.at)
        }
        if since.duration(to: sample.at) >= configuration.degradeFailureTimeout,
           degradeRuleHolds()
        {
            return alarm(reason: .degradeFailed, at: sample.at)
        }
        guard since.duration(to: sample.at) >= dwell, recoveryRuleHolds() else {
            return nil
        }

        state = .normal
        resetCurrentEpisodeSamples()
        return .restore
    }

    private func append(_ sample: CPUSample) {
        samples.append(sample)
        let largestWindow = max(configuration.degradeWindow, configuration.recoveryWindow)
        let windowStart = sample.at.advanced(by: .zero - largestWindow)
        samples.removeAll { $0.at < windowStart }
    }

    private func updateConsecutiveSampleCounts(with sample: CPUSample) {
        consecutiveAlarmSamples = sample.cpuPercent > configuration.alarmThresholdPercent
            ? consecutiveAlarmSamples + 1
            : 0
        consecutiveUnresponsiveSamples = sample.mainThreadResponsive
            ? 0
            : consecutiveUnresponsiveSamples + 1
    }

    private func shouldAlarmForUnresponsiveMainThread(latestCPUPercent: Double) -> Bool {
        consecutiveUnresponsiveSamples >= configuration.mainThreadUnresponsiveSamplesBeforeAlarm
            && latestCPUPercent > configuration.degradeThresholdPercent
    }

    private func degradeRuleHolds() -> Bool {
        let expectedSamples = sampleCount(
            for: configuration.degradeWindow,
            minimum: configuration.degradeWindowMinimumHits
        )
        let trailingSamples = Array(samples.suffix(expectedSamples))
        guard trailingSamples.count == expectedSamples else { return false }
        return trailingSamples.count { $0.cpuPercent > configuration.degradeThresholdPercent }
            >= configuration.degradeWindowMinimumHits
    }

    private func recoveryRuleHolds() -> Bool {
        let expectedSamples = sampleCount(
            for: configuration.recoveryWindow,
            minimum: configuration.recoveryWindowRequiredHits
        )
        let trailingSamples = Array(samples.suffix(expectedSamples))
        guard trailingSamples.count == expectedSamples else { return false }
        return trailingSamples.allSatisfy {
            $0.cpuPercent <= configuration.degradeThresholdPercent
        }
    }

    private func sampleCount(for window: Duration, minimum: Int) -> Int {
        max(Int((window / configuration.sampleInterval).rounded(.up)), minimum)
    }

    private func dwellForEpisode(startingAt date: ContinuousClock.Instant) -> Duration {
        let horizonStart = date.advanced(by: .zero - configuration.dwellDoublingHorizon)
        degradedEpisodeStarts.removeAll { $0 < horizonStart }

        var dwell = configuration.minimumDegradedDwell
        for _ in degradedEpisodeStarts where dwell < configuration.maximumDwell {
            dwell = min(dwell * 2, configuration.maximumDwell)
        }
        return dwell
    }

    private func alarm(reason: AlarmReason, at date: ContinuousClock.Instant) -> Action {
        state = .alarmed
        let restartWindowStart = date.advanced(by: .zero - configuration.restartLoopWindow)
        if restartLedger.restarts(since: restartWindowStart) >= configuration.restartLoopLimit {
            return .alarmAndQuit(reason: reason)
        }
        return .alarmAndRestart(reason: reason)
    }

    private func resetCurrentEpisodeSamples() {
        samples.removeAll(keepingCapacity: true)
        consecutiveAlarmSamples = 0
        consecutiveUnresponsiveSamples = 0
    }
}
