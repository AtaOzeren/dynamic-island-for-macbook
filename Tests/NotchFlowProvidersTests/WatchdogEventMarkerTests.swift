import Foundation
import Testing
@testable import NotchFlowCore
@testable import NotchFlowProviders

@Suite("WatchdogEventMarker")
struct WatchdogEventMarkerTests {
    private func makeTempDirectory(createOnDisk: Bool) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchdogEventMarkerTests-\(UUID().uuidString)", isDirectory: true)
        if createOnDisk {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    @Test("writes a marker and reads it back with every field intact")
    func roundTripsThroughDisk() {
        let directory = makeTempDirectory(createOnDisk: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = WatchdogEventMarker(directoryURL: directory)
        let at = Date(timeIntervalSince1970: 1_700_000_000)

        marker.write(
            WatchdogEventMarker.Event(
                action: .relaunch,
                reason: "cpu alarm",
                at: at,
                reportPath: "/tmp/cpu-alarm.txt"
            )
        )

        let consumed = WatchdogEventMarker(directoryURL: directory).consume()
        #expect(consumed?.action == .relaunch)
        #expect(consumed?.reason == "cpu alarm")
        #expect(consumed?.at == at)
        #expect(consumed?.reportPath == "/tmp/cpu-alarm.txt")
    }

    @Test("preserves a quit action without a report path")
    func roundTripsQuitWithoutReportPath() {
        let directory = makeTempDirectory(createOnDisk: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = WatchdogEventMarker(directoryURL: directory)

        marker.write(
            WatchdogEventMarker.Event(
                action: .quit,
                reason: "restart loop",
                at: Date(timeIntervalSince1970: 1_700_000_000),
                reportPath: nil
            )
        )

        let consumed = marker.consume()
        #expect(consumed?.action == .quit)
        #expect(consumed?.reason == "restart loop")
        #expect(consumed?.reportPath == nil)
    }

    @Test("deletes the marker on read so the notice never fires twice")
    func consumesMarkerOnRead() {
        let directory = makeTempDirectory(createOnDisk: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = WatchdogEventMarker(directoryURL: directory)
        marker.write(
            WatchdogEventMarker.Event(
                action: .relaunch,
                reason: "cpu alarm",
                at: Date(timeIntervalSince1970: 1_700_000_000),
                reportPath: nil
            )
        )

        #expect(marker.consume() != nil)
        #expect(FileManager.default.fileExists(atPath: marker.fileURL.path) == false)
        #expect(marker.consume() == nil)
    }

    @Test("returns nil when no marker was written")
    func returnsNilWhenAbsent() {
        let directory = makeTempDirectory(createOnDisk: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(WatchdogEventMarker(directoryURL: directory).consume() == nil)
    }

    @Test("ignores a corrupt marker and still deletes it")
    func ignoresAndDeletesCorruptMarker() {
        let directory = makeTempDirectory(createOnDisk: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = WatchdogEventMarker(directoryURL: directory)
        try? Data("not json".utf8).write(to: marker.fileURL)

        #expect(marker.consume() == nil)
        #expect(FileManager.default.fileExists(atPath: marker.fileURL.path) == false)
    }

    @Test("creates the marker directory when it does not exist")
    func createsMissingDirectory() {
        let directory = makeTempDirectory(createOnDisk: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = WatchdogEventMarker(directoryURL: directory)

        marker.write(
            WatchdogEventMarker.Event(
                action: .quit,
                reason: "restart loop",
                at: Date(timeIntervalSince1970: 1_700_000_000),
                reportPath: nil
            )
        )

        #expect(FileManager.default.fileExists(atPath: marker.fileURL.path))
        #expect(marker.consume()?.action == .quit)
    }
}
