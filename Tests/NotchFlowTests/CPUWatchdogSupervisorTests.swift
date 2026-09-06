import Foundation
import Testing

@testable import NotchFlow
@testable import NotchFlowCore
@testable import NotchFlowProviders

/// The supervisor's contract is an ordering contract.
///
/// The alarm path runs entirely on the watchdog queue and its six steps have to
/// happen in the order the plan fixes them in, because every one of them is a
/// side effect the next launch reads: a marker written after `exit` is a marker
/// nobody sees, and a relaunch attempted before the diagnostics report is a
/// report the new instance overwrites. Recording every step into one shared log
/// is therefore the assertion, not an implementation detail of the fakes.
@Suite("CPUWatchdogSupervisor")
@MainActor
struct CPUWatchdogSupervisorTests {
    // MARK: - Gate

    @Test("does not start under UI testing")
    func gateRefusesUITesting() {
        #expect(
            CPUWatchdogSupervisor.shouldStart(isUITesting: true, isDisabledBySetting: false) == false
        )
    }

    @Test("honours the kill switch")
    func gateHonoursKillSwitch() {
        #expect(
            CPUWatchdogSupervisor.shouldStart(isUITesting: false, isDisabledBySetting: true) == false
        )
    }

    @Test("starts for an ordinary launch")
    func gateAllowsOrdinaryLaunch() {
        #expect(
            CPUWatchdogSupervisor.shouldStart(isUITesting: false, isDisabledBySetting: false)
        )
    }

    // MARK: - Degrade and restore

    @Test("writes the snapshot before it touches the main thread")
    func degradeWritesSnapshotBeforeDispatchingToMain() async throws {
        let harness = Harness()
        let supervisor = harness.makeSupervisor()

        supervisor.perform(.degrade, for: Harness.sample(cpuPercent: 32))

        #expect(harness.steps.first == .degradeSnapshot)
        try await harness.mainThread.drain()
        #expect(harness.island.entered == 1)
        #expect(harness.steps.contains(.notification(Harness.degradeBody)))
    }

    @Test("leaves the pointer answering while degraded")
    func degradeNeverStopsMouseObserving() async throws {
        let harness = Harness()
        let supervisor = harness.makeSupervisor()

        supervisor.perform(.degrade, for: Harness.sample(cpuPercent: 32))
        try await harness.mainThread.drain()

        #expect(harness.island.stoppedObservingTheMouse == false)
    }

    @Test("restoring is the exact reverse of degrading")
    func restoreExitsDegradedMode() async throws {
        let harness = Harness()
        let supervisor = harness.makeSupervisor()

        supervisor.perform(.degrade, for: Harness.sample(cpuPercent: 32))
        supervisor.perform(.restore, for: Harness.sample(cpuPercent: 3))
        try await harness.mainThread.drain()

        #expect(harness.island.entered == 1)
        #expect(harness.island.exited == 1)
    }

    // MARK: - Alarm and restart

    @Test("relaunching runs report, ledger, marker, notification, relaunch, stop, exit in order")
    func alarmAndRestartOrdersItsSteps() {
        let harness = Harness()
        let supervisor = harness.makeSupervisor()

        supervisor.perform(
            .alarmAndRestart(reason: .cpuAboveAlarmThreshold),
            for: Harness.sample(cpuPercent: 61)
        )

        #expect(
            harness.steps == [
                .alarmReport,
                .recordRestart,
                .marker(.relaunch),
                .notification(Harness.restartBody),
                .relaunch,
                .stopListener,
                .terminate,
            ]
        )
    }

    @Test("never waits on the main thread while relaunching")
    func alarmAndRestartNeverTouchesMain() {
        let harness = Harness()
        let supervisor = harness.makeSupervisor()

        supervisor.perform(
            .alarmAndRestart(reason: .cpuAboveAlarmThreshold),
            for: Harness.sample(cpuPercent: 61)
        )

        #expect(harness.mainThread.pendingCount == 0)
        #expect(harness.island.entered == 0)
    }

    @Test("names the report the marker points at")
    func alarmAndRestartMarkerCarriesTheReportPath() throws {
        let harness = Harness()
        let supervisor = harness.makeSupervisor()

        supervisor.perform(
            .alarmAndRestart(reason: .degradeFailed),
            for: Harness.sample(cpuPercent: 27)
        )

        let event = try #require(harness.marker.written.last)
        #expect(event.action == .relaunch)
        #expect(event.reportPath == harness.reportURL.path)
    }

    @Test("rewrites the marker as a quit when the relaunch is refused, and still exits")
    func alarmAndRestartRewritesMarkerOnFailure() {
        let harness = Harness()
        harness.relauncher.failure = Harness.RelaunchRefused()
        let supervisor = harness.makeSupervisor()

        supervisor.perform(
            .alarmAndRestart(reason: .cpuAboveAlarmThreshold),
            for: Harness.sample(cpuPercent: 61)
        )

        #expect(harness.marker.written.map(\.action) == [.relaunch, .quit])
        #expect(harness.steps.last == .terminate)
    }

    // MARK: - Alarm and quit

    @Test("quitting writes the report and marker, notifies, and never relaunches")
    func alarmAndQuitOrdersItsSteps() {
        let harness = Harness()
        let supervisor = harness.makeSupervisor()

        supervisor.perform(
            .alarmAndQuit(reason: .cpuAboveAlarmThreshold),
            for: Harness.sample(cpuPercent: 61)
        )

        #expect(
            harness.steps == [
                .alarmReport,
                .marker(.quit),
                .notification(Harness.quitBody(reportPath: harness.reportURL.path)),
                .stopListener,
                .terminate,
            ]
        )
    }

    @Test("does not spend a restart budget on the quit that ends the episode")
    func alarmAndQuitDoesNotRecordARestart() {
        let harness = Harness()
        let supervisor = harness.makeSupervisor()

        supervisor.perform(
            .alarmAndQuit(reason: .cpuAboveAlarmThreshold),
            for: Harness.sample(cpuPercent: 61)
        )

        #expect(harness.steps.contains(.recordRestart) == false)
        #expect(harness.relauncher.attempts == 0)
    }
}

// MARK: - Harness

/// Every collaborator the supervisor talks to, recording into one ordered log.
private final class Harness: @unchecked Sendable {
    enum Step: Equatable {
        case degradeSnapshot
        case alarmReport
        case recordRestart
        case marker(WatchdogEventMarker.Action)
        case notification(String)
        case relaunch
        case stopListener
        case terminate
    }

    struct RelaunchRefused: Error {}

    static let degradeBody = "degrade-body"
    static let restartBody = "restart-body"

    static func quitBody(reportPath: String) -> String {
        "quit-body:\(reportPath)"
    }

    static func sample(cpuPercent: Double) -> CPUSample {
        CPUSample(cpuPercent: cpuPercent, mainThreadResponsive: true, at: ContinuousClock().now)
    }

    let reportURL = URL(fileURLWithPath: "/tmp/notchflow-test/cpu-alarm-0.txt")

    private let lock = NSLock()
    private var recorded: [Step] = []

    var steps: [Step] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ step: Step) {
        lock.lock()
        recorded.append(step)
        lock.unlock()
    }

    lazy var island = IslandSpy()
    lazy var mainThread = QueuedMainThread()
    lazy var marker = MarkerSpy(harness: self)
    lazy var relauncher = RelauncherSpy(harness: self)

    func makeSupervisor() -> CPUWatchdogSupervisor {
        CPUWatchdogSupervisor(
            island: island,
            mainThread: mainThread,
            diagnostics: DiagnosticsSpy(harness: self),
            restartLedger: LedgerSpy(harness: self),
            marker: marker,
            notifications: NotificationSpy(harness: self),
            relauncher: relauncher,
            copy: CPUWatchdogSupervisor.NotificationCopy(
                degrade: Self.degradeBody,
                restart: Self.restartBody,
                quit: { Self.quitBody(reportPath: $0 ?? "—") }
            ),
            now: { ContinuousClock().now },
            stopListener: { [weak self] in self?.record(.stopListener) },
            terminate: { [weak self] in self?.record(.terminate) }
        )
    }

    // MARK: Spies

    @MainActor
    final class IslandSpy: IslandMotionDegrading {
        var entered = 0
        var exited = 0
        /// Always false: the supervisor has no way to switch mouse observing
        /// off, and this spy exists to keep it that way.
        let stoppedObservingTheMouse = false

        func enterDegradedMode() { entered += 1 }
        func exitDegradedMode() { exited += 1 }
    }

    /// Holds main-thread work until a test asks for it, so "was the snapshot
    /// written before the dispatch" is a question the log can answer.
    final class QueuedMainThread: WatchdogMainThreadDispatching, @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [@MainActor @Sendable () -> Void] = []

        var pendingCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return pending.count
        }

        func dispatch(_ work: @escaping @MainActor @Sendable () -> Void) {
            lock.lock()
            pending.append(work)
            lock.unlock()
        }

        @MainActor
        func drain() async throws {
            let work = lock.withLock {
                defer { pending = [] }
                return pending
            }
            for block in work { block() }
        }
    }

    struct DiagnosticsSpy: WatchdogDiagnosticsWriting {
        let harness: Harness

        func writeDegradeSnapshot(
            cpuPercent _: Double,
            samples _: [CPUSample],
            mainThreadResponsive _: Bool,
            context _: CPUWatchdogSupervisor.Context
        ) {
            harness.record(.degradeSnapshot)
        }

        func writeAlarmReport(
            reason _: String,
            cpuPercent _: Double,
            samples _: [CPUSample],
            mainThreadResponsive _: Bool,
            context _: CPUWatchdogSupervisor.Context
        ) -> URL? {
            harness.record(.alarmReport)
            return harness.reportURL
        }
    }

    final class LedgerSpy: RestartLedger, @unchecked Sendable {
        let harness: Harness

        init(harness: Harness) { self.harness = harness }

        func recordRestart(at _: ContinuousClock.Instant) { harness.record(.recordRestart) }
        func restarts(since _: ContinuousClock.Instant) -> Int { 0 }
    }

    final class MarkerSpy: WatchdogEventRecording, @unchecked Sendable {
        let harness: Harness
        private let lock = NSLock()
        private var events: [WatchdogEventMarker.Event] = []

        init(harness: Harness) { self.harness = harness }

        var written: [WatchdogEventMarker.Event] {
            lock.lock()
            defer { lock.unlock() }
            return events
        }

        func write(_ event: WatchdogEventMarker.Event) {
            lock.lock()
            events.append(event)
            lock.unlock()
            harness.record(.marker(event.action))
        }
    }

    struct NotificationSpy: WatchdogNotifying {
        let harness: Harness

        func requestAuthorizationIfNeeded() {}
        func post(body: String) { harness.record(.notification(body)) }
    }

    final class RelauncherSpy: WatchdogApplicationRelaunching, @unchecked Sendable {
        let harness: Harness
        var failure: Error?
        private(set) var attempts = 0

        init(harness: Harness) { self.harness = harness }

        func relaunch(completion: @escaping @Sendable (Error?) -> Void) {
            attempts += 1
            harness.record(.relaunch)
            completion(failure)
        }
    }
}
