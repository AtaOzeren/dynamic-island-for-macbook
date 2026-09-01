import AppKit
import Foundation
import Testing

@testable import NotchFlowProviders

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

    @Test("ends recording and cancels detection when the capture UI terminates")
    func terminationEndsRecordingAndCancelsDetection() {
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

        #expect(emissions == [RecordingSession(startedAt: Self.now), nil])
        #expect(scheduler.isScheduled == false)
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
