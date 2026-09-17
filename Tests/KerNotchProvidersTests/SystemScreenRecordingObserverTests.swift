import AppKit
import Foundation
import Testing

@testable import KerNotchProviders

@Suite("SystemScreenRecordingObserver")
@MainActor
struct SystemScreenRecordingObserverTests {
    private static let now = Date(timeIntervalSince1970: 1_000)

    private struct FakeRunningApplication: RunningApplicationDescribing {
        let bundleIdentifier: String?
    }

    private final class RunningApplicationsState: @unchecked Sendable {
        var bundleIdentifiers: Set<String> = []
    }

    private final class CaptureState {
        var isRecording = false
    }

    @Test("recognizes only ReplayKit recording movies")
    func replayRecordingPathClassification() {
        let recording = "/Users/test/Library/Group Containers/group.com.apple.screencapture/ScreenRecordings/session.mov"
        let screenshot = "/Users/test/Library/Group Containers/group.com.apple.screencapture/Screenshots/image.png"
        let unrelatedMovie = "/Users/test/Movies/session.mov"

        #expect(replayRecordingPathIsActive(recording))
        #expect(replayRecordingPathIsActive(screenshot) == false)
        #expect(replayRecordingPathIsActive(unrelatedMovie) == false)
    }

    @Test("does not report the screenshot toolbar as a screen recording")
    func screenshotToolbarDoesNotEmitRecording() {
        let bundleIdentifier = "com.example.screen-recorder"
        let application = FakeRunningApplication(bundleIdentifier: bundleIdentifier)
        let center = NotificationCenter()
        let capture = CaptureState()
        let scheduler = FakeTickScheduler()
        let observer = SystemScreenRecordingObserver(
            workspaceCenter: center,
            runningBundleIdentifiers: { [] },
            isScreenRecording: { capture.isRecording },
            scheduler: scheduler,
            recorderBundleIdentifiers: [bundleIdentifier],
            now: { Self.now }
        )
        var emissions: [RecordingSession?] = []
        observer.startObserving { emissions.append($0) }

        center.post(
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: application]
        )

        #expect(emissions.isEmpty)
        #expect(scheduler.isScheduled)
    }

    @Test("arms detection when the capture UI appears without a launch notification")
    func runningApplicationsChangeArmsDetection() {
        let bundleIdentifier = "com.example.screen-recorder"
        let center = NotificationCenter()
        let runningApplications = RunningApplicationsState()
        let capture = CaptureState()
        let scheduler = FakeTickScheduler()
        var reconcileRunningApplications: (@MainActor @Sendable () -> Void)?
        let observer = SystemScreenRecordingObserver(
            workspaceCenter: center,
            runningBundleIdentifiers: { runningApplications.bundleIdentifiers },
            observeRunningApplications: { reconciliation in
                reconcileRunningApplications = reconciliation
                return nil
            },
            isScreenRecording: { capture.isRecording },
            scheduler: scheduler,
            recorderBundleIdentifiers: [bundleIdentifier],
            now: { Self.now }
        )
        var emissions: [RecordingSession?] = []
        observer.startObserving { emissions.append($0) }

        runningApplications.bundleIdentifiers.insert(bundleIdentifier)
        reconcileRunningApplications?()

        #expect(emissions.isEmpty)
        #expect(scheduler.isScheduled)
    }

    @Test("reports video capture only after ReplayKit starts recording")
    func activeReplayCaptureEmitsRecording() {
        let bundleIdentifier = "com.example.screen-recorder"
        let center = NotificationCenter()
        let capture = CaptureState()
        let scheduler = FakeTickScheduler()
        let observer = SystemScreenRecordingObserver(
            workspaceCenter: center,
            runningBundleIdentifiers: { [bundleIdentifier] },
            isScreenRecording: { capture.isRecording },
            scheduler: scheduler,
            recorderBundleIdentifiers: [bundleIdentifier],
            now: { Self.now }
        )
        var emissions: [RecordingSession?] = []
        observer.startObserving { emissions.append($0) }

        capture.isRecording = true
        scheduler.fire()

        #expect(emissions == [RecordingSession(startedAt: Self.now)])
    }

    @Test("ends video capture while leaving the screenshot toolbar unreported")
    func replayCaptureEndEmitsNilWhileToolbarRemainsOpen() {
        let bundleIdentifier = "com.example.screen-recorder"
        let center = NotificationCenter()
        let capture = CaptureState()
        capture.isRecording = true
        let scheduler = FakeTickScheduler()
        let observer = SystemScreenRecordingObserver(
            workspaceCenter: center,
            runningBundleIdentifiers: { [bundleIdentifier] },
            isScreenRecording: { capture.isRecording },
            scheduler: scheduler,
            recorderBundleIdentifiers: [bundleIdentifier],
            now: { Self.now }
        )
        var emissions: [RecordingSession?] = []
        observer.startObserving { emissions.append($0) }

        capture.isRecording = false
        scheduler.fire()

        #expect(emissions == [RecordingSession(startedAt: Self.now), nil])
        #expect(scheduler.isScheduled)
    }

    /// The reported defect. The screenshot toolbar quits once recording is
    /// under way — the capture is carried by `screencapture` and `replayd` —
    /// and treating its absence as "not recording" took the indicator off the
    /// island for the rest of the session.
    @Test("a recording outlives the capture UI that started it")
    func recordingSurvivesCaptureUITermination() {
        let bundleIdentifier = "com.example.screen-recorder"
        let application = FakeRunningApplication(bundleIdentifier: bundleIdentifier)
        let center = NotificationCenter()
        let capture = CaptureState()
        capture.isRecording = true
        let scheduler = FakeTickScheduler()
        let observer = SystemScreenRecordingObserver(
            workspaceCenter: center,
            runningBundleIdentifiers: { [bundleIdentifier] },
            isScreenRecording: { capture.isRecording },
            scheduler: scheduler,
            recorderBundleIdentifiers: [bundleIdentifier],
            now: { Self.now }
        )
        var emissions: [RecordingSession?] = []
        observer.startObserving { emissions.append($0) }

        center.post(
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: application]
        )

        #expect(emissions == [RecordingSession(startedAt: Self.now)], "the toolbar quitting ended the recording")
        #expect(scheduler.isScheduled, "nothing was left watching for the recording to end")

        capture.isRecording = false
        scheduler.fire()

        #expect(emissions == [RecordingSession(startedAt: Self.now), nil])
        #expect(scheduler.isScheduled == false, "the tick outlived the recording")
    }

    /// A recording already under way when KerNotch starts is one the user is in
    /// the middle of, and there is no edge left to wait for.
    @Test("reports a recording that was already running when observation starts")
    func recordingInProgressAtStartIsReported() {
        let capture = CaptureState()
        capture.isRecording = true
        let scheduler = FakeTickScheduler()
        let observer = SystemScreenRecordingObserver(
            workspaceCenter: NotificationCenter(),
            runningBundleIdentifiers: { [] },
            isScreenRecording: { capture.isRecording },
            scheduler: scheduler,
            recorderBundleIdentifiers: ["com.example.screen-recorder"],
            now: { Self.now }
        )
        var emissions: [RecordingSession?] = []

        observer.startObserving { emissions.append($0) }

        #expect(emissions == [RecordingSession(startedAt: Self.now)])
        #expect(scheduler.isScheduled, "a live recording needs watching for its end")
    }

    /// The folder the system records into is the signal that needs no capture
    /// UI at all: the movie appears there when recording starts.
    @Test("a change in the recordings folder is read as a recording")
    func recordingsFolderChangeIsSampled() {
        let capture = CaptureState()
        let scheduler = FakeTickScheduler()
        let watcher = FakeRecordingsDirectoryWatcher()
        let observer = SystemScreenRecordingObserver(
            workspaceCenter: NotificationCenter(),
            runningBundleIdentifiers: { [] },
            isScreenRecording: { capture.isRecording },
            scheduler: scheduler,
            directoryWatcher: watcher,
            recorderBundleIdentifiers: ["com.example.screen-recorder"],
            now: { Self.now }
        )
        var emissions: [RecordingSession?] = []
        observer.startObserving { emissions.append($0) }

        #expect(emissions.isEmpty)
        #expect(scheduler.isScheduled == false, "an idle island kept a timer")

        capture.isRecording = true
        watcher.reportChange()

        #expect(emissions == [RecordingSession(startedAt: Self.now)])
        #expect(watcher.isWatching)
    }

    /// The reported delay. The folder changes the moment a recording starts,
    /// but `replayd` opens the movie a beat later, so the first reading can
    /// still say "no". Cancelling the tick on that reading left the indicator
    /// waiting for whatever happened next — about five seconds, in practice.
    @Test("keeps reading the probe after the recordings folder changes")
    func folderChangeKeepsReadingTheProbe() {
        let capture = CaptureState()
        let scheduler = FakeTickScheduler()
        let watcher = FakeRecordingsDirectoryWatcher()
        let clock = FakeClock(now: Self.now)
        let observer = SystemScreenRecordingObserver(
            workspaceCenter: NotificationCenter(),
            runningBundleIdentifiers: { [] },
            isScreenRecording: { capture.isRecording },
            scheduler: scheduler,
            directoryWatcher: watcher,
            recorderBundleIdentifiers: ["com.example.screen-recorder"],
            now: { clock.now }
        )
        var emissions: [RecordingSession?] = []
        observer.startObserving { emissions.append($0) }

        // The movie appears, but the recording is not under way yet.
        watcher.reportChange()

        #expect(emissions.isEmpty)
        #expect(scheduler.isScheduled, "nothing was left to notice the recording starting")

        capture.isRecording = true
        scheduler.fire()

        #expect(emissions == [RecordingSession(startedAt: Self.now)])
    }

    /// And the window closes: a folder touched for some other reason costs a
    /// few readings, not a timer that runs for the rest of the session.
    @Test("stops reading once the settling window is over")
    func settlingWindowCloses() {
        let scheduler = FakeTickScheduler()
        let watcher = FakeRecordingsDirectoryWatcher()
        let clock = FakeClock(now: Self.now)
        let observer = SystemScreenRecordingObserver(
            workspaceCenter: NotificationCenter(),
            runningBundleIdentifiers: { [] },
            isScreenRecording: { false },
            scheduler: scheduler,
            directoryWatcher: watcher,
            recorderBundleIdentifiers: ["com.example.screen-recorder"],
            now: { clock.now }
        )
        observer.startObserving { _ in }

        watcher.reportChange()
        #expect(scheduler.isScheduled)

        clock.now = Self.now.addingTimeInterval(30)
        scheduler.fire()

        #expect(scheduler.isScheduled == false)
    }

    @Test("stops watching the recordings folder when observation stops")
    func stoppingObservationStopsTheFolderWatch() {
        let watcher = FakeRecordingsDirectoryWatcher()
        let observer = SystemScreenRecordingObserver(
            workspaceCenter: NotificationCenter(),
            runningBundleIdentifiers: { [] },
            isScreenRecording: { false },
            scheduler: FakeTickScheduler(),
            directoryWatcher: watcher,
            recorderBundleIdentifiers: ["com.example.screen-recorder"],
            now: { Self.now }
        )

        observer.startObserving { _ in }
        #expect(watcher.isWatching)

        observer.stopObserving()

        #expect(watcher.isWatching == false)
    }
}

private final class FakeClock: @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private final class FakeRecordingsDirectoryWatcher: RecordingsDirectoryWatching {
    private var onChange: (@MainActor () -> Void)?

    var isWatching: Bool { onChange != nil }

    func startWatching(_ onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    func stopWatching() {
        onChange = nil
    }

    func reportChange() {
        onChange?()
    }
}

@MainActor
private final class FakeTickScheduler: TickScheduling {
    private var tick: (@MainActor () -> Void)?

    var isScheduled: Bool { tick != nil }

    func schedule(_ tick: @escaping @MainActor () -> Void) {
        self.tick = tick
    }

    func cancel() {
        tick = nil
    }

    func fire() {
        tick?()
    }
}
