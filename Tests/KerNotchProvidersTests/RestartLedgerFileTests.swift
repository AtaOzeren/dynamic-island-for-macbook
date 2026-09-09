import Foundation
import Testing
@testable import KerNotchCore
@testable import KerNotchProviders

@Suite("RestartLedgerFile")
struct RestartLedgerFileTests {
    private func makeTempDirectory(createOnDisk: Bool) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestartLedgerFileTests-\(UUID().uuidString)", isDirectory: true)
        if createOnDisk {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private func makeLedger(
        directory: URL,
        anchor: ContinuousClock.Instant,
        now: @escaping @Sendable () -> Date
    ) -> RestartLedgerFile {
        RestartLedgerFile(
            directoryURL: directory,
            window: .seconds(3600),
            referenceInstant: anchor,
            now: now
        )
    }

    @Test("writes restarts to disk and reads them back within the window")
    func roundTripsThroughDisk() {
        let directory = makeTempDirectory(createOnDisk: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let anchor = ContinuousClock().now
        let wallClock = Date(timeIntervalSince1970: 1_700_000_000)
        let ledger = makeLedger(directory: directory, anchor: anchor, now: { wallClock })

        ledger.recordRestart(at: anchor)
        ledger.recordRestart(at: anchor.advanced(by: .seconds(10)))

        let reader = makeLedger(directory: directory, anchor: anchor, now: { wallClock })
        #expect(reader.restarts(since: anchor.advanced(by: .seconds(-60))) == 2)
        #expect(FileManager.default.fileExists(atPath: ledger.fileURL.path))
    }

    @Test("counts only restarts at or after the requested instant")
    func countsOnlyRestartsInsideTheRequestedRange() {
        let directory = makeTempDirectory(createOnDisk: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let anchor = ContinuousClock().now
        let wallClock = Date(timeIntervalSince1970: 1_700_000_000)
        let ledger = makeLedger(directory: directory, anchor: anchor, now: { wallClock })

        ledger.recordRestart(at: anchor.advanced(by: .seconds(-1800)))
        ledger.recordRestart(at: anchor.advanced(by: .seconds(-60)))

        #expect(ledger.restarts(since: anchor.advanced(by: .seconds(-3600))) == 2)
        #expect(ledger.restarts(since: anchor.advanced(by: .seconds(-600))) == 1)
        #expect(ledger.restarts(since: anchor) == 0)
    }

    @Test("prunes entries older than the restart-loop window on write")
    func prunesEntriesOutsideTheWindow() throws {
        let directory = makeTempDirectory(createOnDisk: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let anchor = ContinuousClock().now
        let wallClock = Date(timeIntervalSince1970: 1_700_000_000)
        let ledger = makeLedger(directory: directory, anchor: anchor, now: { wallClock })

        ledger.recordRestart(at: anchor.advanced(by: .seconds(-7200)))
        ledger.recordRestart(at: anchor)

        let contents = try Data(contentsOf: ledger.fileURL)
        let stored = try JSONDecoder().decode([String].self, from: contents)
        #expect(stored.count == 1)
        #expect(ledger.restarts(since: anchor.advanced(by: .seconds(-86400))) == 1)
    }

    @Test("treats a corrupt ledger file as empty and recovers on the next write")
    func treatsCorruptFileAsEmpty() {
        let directory = makeTempDirectory(createOnDisk: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let anchor = ContinuousClock().now
        let wallClock = Date(timeIntervalSince1970: 1_700_000_000)
        let ledger = makeLedger(directory: directory, anchor: anchor, now: { wallClock })
        try? Data("not json".utf8).write(to: ledger.fileURL)

        #expect(ledger.restarts(since: anchor.advanced(by: .seconds(-3600))) == 0)

        ledger.recordRestart(at: anchor)
        #expect(ledger.restarts(since: anchor.advanced(by: .seconds(-3600))) == 1)
    }

    @Test("treats a missing ledger file as empty")
    func treatsMissingFileAsEmpty() {
        let directory = makeTempDirectory(createOnDisk: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let anchor = ContinuousClock().now
        let ledger = makeLedger(
            directory: directory,
            anchor: anchor,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        #expect(ledger.restarts(since: anchor.advanced(by: .seconds(-3600))) == 0)
    }

    @Test("creates the ledger directory when it does not exist")
    func createsMissingDirectory() {
        let directory = makeTempDirectory(createOnDisk: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let anchor = ContinuousClock().now
        let ledger = makeLedger(
            directory: directory,
            anchor: anchor,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        #expect(FileManager.default.fileExists(atPath: directory.path) == false)

        ledger.recordRestart(at: anchor)

        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(FileManager.default.fileExists(atPath: ledger.fileURL.path))
        #expect(ledger.restarts(since: anchor.advanced(by: .seconds(-3600))) == 1)
    }
}
