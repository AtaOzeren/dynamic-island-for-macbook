import Foundation
import Testing

@testable import KerNotchCore
@testable import KerNotchProviders

@Suite("RunawayDiagnostics")
struct RunawayDiagnosticsTests {
    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunawayDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSample(cpuPercent: Double, secondsBeforeNewest: Int64 = 0) -> CPUSample {
        CPUSample(
            cpuPercent: cpuPercent,
            mainThreadResponsive: true,
            at: ContinuousClock().now - .seconds(secondsBeforeNewest)
        )
    }

    private func makeConfiguration(
        directory: URL,
        flavour: RunawayDiagnostics.BuildFlavour = .direct,
        sampleWaitTimeoutSeconds: TimeInterval = 5,
        runner: @escaping @Sendable (pid_t, URL) -> Void = { _, _ in }
    ) -> RunawayDiagnostics.Configuration {
        RunawayDiagnostics.Configuration(
            directoryURL: directory,
            flavour: flavour,
            sampleWaitTimeoutSeconds: sampleWaitTimeoutSeconds,
            runSampleTool: runner
        )
    }

    @Test("snapshot writes a cpu-degrade file into the diagnostics directory")
    func snapshotCreatesDegradeFile() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = RunawayDiagnostics(
            configuration: makeConfiguration(directory: directory)
        )

        try diagnostics.writeSnapshot(
            cpuPercent: 24.5,
            sampleHistory: [makeSample(cpuPercent: 24.5)],
            transitions: ["normal -> degraded"],
            mainThreadResponsive: true,
            displayTarget: "builtin",
            activityKinds: ["recording"]
        )

        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(entries.count == 1)
        #expect(entries[0].lastPathComponent.hasPrefix("cpu-degrade-"))
        #expect(entries[0].lastPathComponent.hasSuffix(".txt"))
        let text = try String(contentsOf: entries[0], encoding: .utf8)
        #expect(!text.isEmpty)
    }

    @Test("full report contains the per-thread table and privacy-safe context")
    func fullReportContainsThreadTable() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = RunawayDiagnostics(
            configuration: makeConfiguration(directory: directory)
        )

        let reportURL = try diagnostics.writeFullReport(
            cpuPercent: 201.3,
            sampleHistory: [
                makeSample(cpuPercent: 190, secondsBeforeNewest: 5),
                makeSample(cpuPercent: 201.3),
            ],
            transitions: ["normal -> degraded", "degraded -> alarmed"],
            mainThreadResponsive: false,
            displayTarget: "Studio Display",
            activityKinds: ["recording", "ai-agent"],
            reason: "cpuAboveAlarmThreshold"
        )

        #expect(reportURL.lastPathComponent.hasPrefix("cpu-alarm-"))
        #expect(FileManager.default.fileExists(atPath: reportURL.path))
        let text = try String(contentsOf: reportURL, encoding: .utf8)
        #expect(text.contains("per-thread CPU"))
        #expect(text.contains("reason: cpuAboveAlarmThreshold"))
        #expect(text.contains("build flavour: direct"))
        #expect(text.contains("recording, ai-agent"))
        #expect(text.contains("state transitions"))
        #expect(text.contains("sample history"))
    }

    @Test("prune keeps only the newest 20 files after a write")
    func pruneKeepsNewestTwenty() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for index in 1...22 {
            let stale = directory.appendingPathComponent(
                String(format: "cpu-degrade-20250101-0000%02d.txt", index)
            )
            try Data("stale".utf8).write(to: stale)
        }
        let diagnostics = RunawayDiagnostics(
            configuration: makeConfiguration(directory: directory)
        )

        try diagnostics.writeSnapshot(
            cpuPercent: 24.5,
            sampleHistory: [],
            transitions: [],
            mainThreadResponsive: true,
            displayTarget: "builtin",
            activityKinds: []
        )

        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(entries.count == 20)
        let names = entries.map(\.lastPathComponent)
        #expect(!names.contains("cpu-degrade-20250101-000001.txt"))
        #expect(!names.contains("cpu-degrade-20250101-000002.txt"))
        #expect(!names.contains("cpu-degrade-20250101-000003.txt"))
        #expect(names.contains { !$0.hasPrefix("cpu-degrade-20250101") })
    }

    /// Every `sample-` name sorts above every `cpu-` one, so a prune that
    /// ordered by filename threw away the report it had just written to keep
    /// captures from days earlier — losing the one file the next occurrence
    /// has to be diagnosed from.
    @Test("prune keeps the newest report even when older sample captures fill the budget")
    func pruneOrdersByWriteTimeNotName() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ancient = Date(timeIntervalSince1970: 1_000_000)
        for index in 1...25 {
            let stale = directory.appendingPathComponent(
                String(format: "sample-20250101-0000%02d.txt", index)
            )
            try Data("stale".utf8).write(to: stale)
            try FileManager.default.setAttributes(
                [.modificationDate: ancient.addingTimeInterval(TimeInterval(index))],
                ofItemAtPath: stale.path
            )
        }
        let diagnostics = RunawayDiagnostics(
            configuration: makeConfiguration(directory: directory)
        )

        try diagnostics.writeSnapshot(
            cpuPercent: 24.5,
            sampleHistory: [],
            transitions: [],
            mainThreadResponsive: true,
            displayTarget: "builtin",
            activityKinds: []
        )

        let names = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent)

        #expect(names.count == 20)
        #expect(names.contains { $0.hasPrefix("cpu-degrade-") })
        #expect(!names.contains("sample-20250101-000001.txt"))
    }

    @Test("atomic write leaves no temporary file behind")
    func atomicWriteCleansUpTemporaryFile() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = RunawayDiagnostics(
            configuration: makeConfiguration(directory: directory)
        )

        try diagnostics.writeSnapshot(
            cpuPercent: 24.5,
            sampleHistory: [],
            transitions: [],
            mainThreadResponsive: true,
            displayTarget: "builtin",
            activityKinds: []
        )

        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(entries.count == 1)
        #expect(!entries[0].lastPathComponent.contains(".tmp"))
        #expect(entries[0].lastPathComponent.hasPrefix("cpu-degrade-"))
    }

    @Test("sample tool runs only for the direct build on the alarm path")
    func sampleToolIsDirectBuildAlarmOnly() throws {
        final class SampleCallLog: @unchecked Sendable {
            private let lock = NSLock()
            private var recordedURLs: [URL] = []
            func record(_ url: URL) {
                lock.lock()
                defer { lock.unlock() }
                recordedURLs.append(url)
            }
            var urls: [URL] {
                lock.lock()
                defer { lock.unlock() }
                return recordedURLs
            }
        }

        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calls = SampleCallLog()
        let runner: @Sendable (pid_t, URL) -> Void = { _, url in calls.record(url) }

        let appStoreDiagnostics = RunawayDiagnostics(
            configuration: makeConfiguration(
                directory: directory,
                flavour: .appStore,
                runner: runner
            )
        )
        _ = try appStoreDiagnostics.writeFullReport(
            cpuPercent: 50,
            sampleHistory: [],
            transitions: [],
            mainThreadResponsive: true,
            displayTarget: "builtin",
            activityKinds: [],
            reason: "cpuAboveAlarmThreshold"
        )
        #expect(calls.urls.isEmpty)

        let directDiagnostics = RunawayDiagnostics(
            configuration: makeConfiguration(
                directory: directory,
                flavour: .direct,
                runner: runner
            )
        )
        _ = try directDiagnostics.writeFullReport(
            cpuPercent: 50,
            sampleHistory: [],
            transitions: [],
            mainThreadResponsive: true,
            displayTarget: "builtin",
            activityKinds: [],
            reason: "cpuAboveAlarmThreshold"
        )
        #expect(calls.urls.count == 1)
        #expect(calls.urls[0].lastPathComponent.hasPrefix("sample-"))
        #expect(calls.urls[0].deletingLastPathComponent() == directory)
    }

    @Test("snapshot never runs the sample tool even on the direct build")
    func snapshotSkipsSampleTool() throws {
        final class SampleCallLog: @unchecked Sendable {
            private let lock = NSLock()
            private var count = 0
            func record() {
                lock.lock()
                defer { lock.unlock() }
                count += 1
            }
            var callCount: Int {
                lock.lock()
                defer { lock.unlock() }
                return count
            }
        }

        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let calls = SampleCallLog()
        let diagnostics = RunawayDiagnostics(
            configuration: makeConfiguration(
                directory: directory,
                flavour: .direct,
                runner: { _, _ in calls.record() }
            )
        )

        try diagnostics.writeSnapshot(
            cpuPercent: 24.5,
            sampleHistory: [],
            transitions: [],
            mainThreadResponsive: true,
            displayTarget: "builtin",
            activityKinds: []
        )

        #expect(calls.callCount == 0)
    }

    @Test("full report returns within the sample wait timeout when the tool hangs")
    func fullReportBoundsSampleToolWait() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = RunawayDiagnostics(
            configuration: makeConfiguration(
                directory: directory,
                flavour: .direct,
                sampleWaitTimeoutSeconds: 0.2,
                runner: { _, _ in Thread.sleep(forTimeInterval: 2.0) }
            )
        )

        let start = Date()
        _ = try diagnostics.writeFullReport(
            cpuPercent: 50,
            sampleHistory: [],
            transitions: [],
            mainThreadResponsive: true,
            displayTarget: "builtin",
            activityKinds: [],
            reason: "cpuAboveAlarmThreshold"
        )
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed < 1.5)
    }
}
