import Foundation
import Testing

@testable import KerNotchProviders

/// The file-system half of screen-recording detection, driven against a real
/// directory in a temporary folder.
///
/// The watch is a file descriptor and a dispatch source, so a fake would only
/// prove that the fake works. What is asserted here is the one thing the
/// observer depends on: that creating the movie in the watched folder reaches
/// the handler.
@Suite("ScreenRecordingsDirectoryWatcher")
@MainActor
struct ScreenRecordingsDirectoryWatcherTests {
    private final class ChangeCount: @unchecked Sendable {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    private static func waitForChange(_ changes: ChangeCount) async -> Bool {
        for _ in 0..<40 {
            if changes.value > 0 { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    @Test("reports a movie appearing in the recordings folder")
    func reportsNewRecording() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let changes = ChangeCount()
        let watcher = ScreenRecordingsDirectoryWatcher(path: folder.path)
        watcher.startWatching { changes.increment() }
        defer { watcher.stopWatching() }

        try Data().write(to: folder.appendingPathComponent("session.mov"))

        #expect(await Self.waitForChange(changes), "the watcher never saw the recording appear")
    }

    /// A Mac that has never recorded anything has no recordings folder yet. The
    /// watch waits on the container instead, so the first recording of its life
    /// is still seen.
    @Test("reports the recordings folder itself appearing")
    func reportsFolderCreation() async throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let recordings = container.appendingPathComponent("ScreenRecordings", isDirectory: true)

        let changes = ChangeCount()
        let watcher = ScreenRecordingsDirectoryWatcher(path: recordings.path)
        watcher.startWatching { changes.increment() }
        defer { watcher.stopWatching() }

        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)

        #expect(await Self.waitForChange(changes), "the watcher never saw the folder appear")
    }

    @Test("stops reporting once the watch is stopped")
    func stopsReporting() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let changes = ChangeCount()
        let watcher = ScreenRecordingsDirectoryWatcher(path: folder.path)
        watcher.startWatching { changes.increment() }
        watcher.stopWatching()

        try Data().write(to: folder.appendingPathComponent("session.mov"))
        try? await Task.sleep(for: .milliseconds(200))

        #expect(changes.value == 0)
    }
}

/// The other half of the same fix: the movie in the recordings folder is what
/// says a recording has started, before `replayd` has opened it.
@Suite("Recording movie freshness")
struct RecordingMovieFreshnessTests {
    private static let now = Date(timeIntervalSince1970: 10_000)

    private static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func write(_ name: String, modified: Date, in folder: URL) throws {
        let file = folder.appendingPathComponent(name)
        try Data().write(to: file)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
    }

    @Test("a movie written a moment ago is a recording in progress")
    func freshMovieIsARecording() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Self.write("session.mov", modified: Self.now.addingTimeInterval(-1), in: folder)

        #expect(recordingsFolderHoldsMovieBeingWritten(in: folder.path, at: Self.now, within: 5))
    }

    /// What keeps a movie left behind by a crash from showing a recording that
    /// is not happening: it stops being written, so it stops counting.
    @Test("a movie that stopped being written is not a recording")
    func staleMovieIsNotARecording() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Self.write("session.mov", modified: Self.now.addingTimeInterval(-60), in: folder)

        #expect(recordingsFolderHoldsMovieBeingWritten(in: folder.path, at: Self.now, within: 5) == false)
    }

    @Test("only movies count")
    func onlyMoviesCount() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Self.write("screenshot.png", modified: Self.now, in: folder)

        #expect(recordingsFolderHoldsMovieBeingWritten(in: folder.path, at: Self.now, within: 5) == false)
    }

    @Test("an empty or missing folder is no recording")
    func emptyFolderIsNotARecording() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(recordingsFolderHoldsMovieBeingWritten(in: folder.path, at: Self.now, within: 5) == false)
        #expect(
            recordingsFolderHoldsMovieBeingWritten(
                in: folder.appendingPathComponent("missing").path, at: Self.now, within: 5
            ) == false
        )
    }
}
