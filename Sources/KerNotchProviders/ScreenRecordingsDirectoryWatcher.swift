import Darwin
import Foundation

/// A watch on the folder the system writes its screen recordings into.
///
/// The seam exists because the watch is a file descriptor and a dispatch
/// source: real on a Mac, and nothing a test can drive. Everything the observer
/// decides from it is testable against a fake.
@MainActor
public protocol RecordingsDirectoryWatching: AnyObject {
    func startWatching(_ onChange: @escaping @MainActor () -> Void)
    func stopWatching()
}

/// Watches `~/Library/Group Containers/group.com.apple.screencapture/ScreenRecordings`,
/// where the system opens the movie it is recording into.
///
/// This is what lets KerNotch notice a recording without the capture UI being
/// open. The screenshot toolbar quits once recording is under way — the capture
/// itself is carried by `screencapture` and `replayd` — so an observer that
/// only looked while that application was running reported no recording at all
/// for the entire session.
///
/// A file-system source rather than a poll: it costs nothing until the folder
/// changes, which keeps the idle budget in `docs/02-performance-contract.md`
/// intact.
@MainActor
final class ScreenRecordingsDirectoryWatcher: RecordingsDirectoryWatching {
    static var systemPath: String {
        NSHomeDirectory()
            + "/Library/Group Containers/group.com.apple.screencapture/ScreenRecordings"
    }

    private let path: String
    private var source: DispatchSourceFileSystemObject?
    private var watchedPath: String?
    private var onChange: (@MainActor () -> Void)?

    init(path: String = ScreenRecordingsDirectoryWatcher.systemPath) {
        self.path = path
    }

    deinit {
        source?.cancel()
    }

    func startWatching(_ onChange: @escaping @MainActor () -> Void) {
        stopWatching()
        self.onChange = onChange
        arm()
    }

    func stopWatching() {
        source?.cancel()
        source = nil
        watchedPath = nil
        onChange = nil
    }

    /// Watches the recordings folder, or its container until that folder
    /// exists.
    ///
    /// A Mac that has never recorded anything has no recordings folder to open,
    /// and a watch that failed there would never see the first recording of its
    /// life. The container is created with the group itself, so it is there to
    /// watch in the meantime.
    private func arm() {
        let container = (path as NSString).deletingLastPathComponent
        for candidate in [path, container] {
            let descriptor = open(candidate, O_EVTONLY)
            guard descriptor >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.handleChange() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()

            self.source = source
            watchedPath = candidate
            return
        }
    }

    private func handleChange() {
        // The folder this watch was waiting for has appeared: move the watch
        // onto it, so the next recording is seen in the folder itself.
        if watchedPath != path, FileManager.default.fileExists(atPath: path) {
            let onChange = onChange
            stopWatching()
            self.onChange = onChange
            arm()
        }

        onChange?()
    }
}

/// The watch a test gets by default: none at all, so a test drives the observer
/// through the seams it means to and never through the real file system.
@MainActor
final class InertRecordingsDirectoryWatcher: RecordingsDirectoryWatching {
    func startWatching(_ onChange: @escaping @MainActor () -> Void) {}
    func stopWatching() {}
}
