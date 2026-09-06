import Darwin
import Foundation
import NotchFlowCore
import os

/// Writes CPU runaway diagnostics to `<Library>/Logs/NotchFlow` at degrade
/// time (lightweight snapshot) and at alarm time (full report including a
/// per-thread CPU table and, on the Direct build, a `/usr/bin/sample`
/// capture). The supervisor calls these before any restart or quit: without
/// the report, the restart-loop guard fires and the cause stays unknown.
///
/// Privacy: reports contain process introspection and the values passed in
/// only. Activity kinds are names ("recording", "ai-agent"), never session
/// titles or agent detail — see `docs/07-ai-integration.md`.
public struct RunawayDiagnostics: Sendable {
    public enum BuildFlavour: String, Sendable {
        case direct
        case appStore
    }

    private enum ReportKind: String {
        case degrade
        case alarm

        var filePrefix: String { "cpu-\(rawValue)" }
        var title: String {
            switch self {
            case .degrade: return "degrade snapshot"
            case .alarm: return "alarm report"
            }
        }
    }

    private struct ThreadRow {
        let cpuPercent: Double
        let userSeconds: Double
        let systemSeconds: Double
        let threadID: UInt64
        let name: String
    }

    public struct Configuration: Sendable {
        public let directoryURL: URL
        public let flavour: BuildFlavour
        public let keepNewestFileCount: Int
        public let sampleWaitTimeoutSeconds: TimeInterval
        public let runSampleTool: @Sendable (_ pid: pid_t, _ outputURL: URL) -> Void

        public init(
            directoryURL: URL? = nil,
            flavour: BuildFlavour? = nil,
            keepNewestFileCount: Int = 20,
            sampleWaitTimeoutSeconds: TimeInterval = 15,
            runSampleTool: (@Sendable (_ pid: pid_t, _ outputURL: URL) -> Void)? = nil
        ) {
            self.directoryURL = directoryURL ?? Self.defaultDirectoryURL
            self.flavour = flavour ?? RunawayDiagnostics.detectedBuildFlavour
            self.keepNewestFileCount = keepNewestFileCount
            self.sampleWaitTimeoutSeconds = sampleWaitTimeoutSeconds
            self.runSampleTool = runSampleTool ?? { pid, outputURL in
                RunawayDiagnostics.runSampleProcess(pid: pid, outputURL: outputURL)
            }
        }

        public static var defaultDirectoryURL: URL {
            ApplicationDirectories.logs
        }
    }

    private static let logger = Logger(
        subsystem: "com.notchflow.NotchFlow",
        category: "runaway-diagnostics"
    )

    private let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Direct build in the Xcode sense is invisible to package code
    /// (`#if DIRECT_BUILD` is dead inside SwiftPM targets), so the flavour is
    /// detected at runtime from the App Store receipt.
    public static var detectedBuildFlavour: BuildFlavour {
        guard
            let receiptURL = Bundle.main.appStoreReceiptURL,
            receiptURL.lastPathComponent == "receipt",
            FileManager.default.fileExists(atPath: receiptURL.path)
        else {
            return .direct
        }
        return .appStore
    }

    /// Writes a lightweight snapshot at degrade time.
    public func writeSnapshot(
        cpuPercent: Double,
        sampleHistory: [CPUSample],
        transitions: [String],
        mainThreadResponsive: Bool,
        displayTarget: String,
        activityKinds: [String]
    ) throws {
        _ = try writeReport(
            kind: .degrade,
            cpuPercent: cpuPercent,
            sampleHistory: sampleHistory,
            transitions: transitions,
            mainThreadResponsive: mainThreadResponsive,
            displayTarget: displayTarget,
            activityKinds: activityKinds,
            reason: nil
        )
    }

    /// Writes the full report at alarm time. On the Direct build this also
    /// runs `/usr/bin/sample` for 5 seconds and waits for it, bounded by the
    /// configured timeout, so the caller can relaunch or quit afterwards.
    @discardableResult
    public func writeFullReport(
        cpuPercent: Double,
        sampleHistory: [CPUSample],
        transitions: [String],
        mainThreadResponsive: Bool,
        displayTarget: String,
        activityKinds: [String],
        reason: String
    ) throws -> URL {
        try writeReport(
            kind: .alarm,
            cpuPercent: cpuPercent,
            sampleHistory: sampleHistory,
            transitions: transitions,
            mainThreadResponsive: mainThreadResponsive,
            displayTarget: displayTarget,
            activityKinds: activityKinds,
            reason: reason
        )
    }

    private func writeReport(
        kind: ReportKind,
        cpuPercent: Double,
        sampleHistory: [CPUSample],
        transitions: [String],
        mainThreadResponsive: Bool,
        displayTarget: String,
        activityKinds: [String],
        reason: String?
    ) throws -> URL {
        let stamp = Self.fileStamp(Date())
        let reportURL = configuration.directoryURL
            .appendingPathComponent("\(kind.filePrefix)-\(stamp).txt", isDirectory: false)
        let sampleURL = configuration.directoryURL
            .appendingPathComponent("sample-\(stamp).txt", isDirectory: false)

        let text = Self.reportText(
            kind: kind,
            cpuPercent: cpuPercent,
            sampleHistory: sampleHistory,
            transitions: transitions,
            mainThreadResponsive: mainThreadResponsive,
            displayTarget: displayTarget,
            activityKinds: activityKinds,
            reason: reason,
            writtenAt: Date(),
            pid: ProcessInfo.processInfo.processIdentifier,
            threadRows: kind == .alarm ? Self.collectThreadRows() : [],
            sampleURL: kind == .alarm ? sampleURL : nil,
            flavour: configuration.flavour
        )

        try FileManager.default.createDirectory(
            at: configuration.directoryURL,
            withIntermediateDirectories: true
        )
        try writeAtomically(Data(text.utf8), to: reportURL)
        Self.logger.info("wrote \(kind.title) to \(reportURL.path, privacy: .public)")

        if kind == .alarm {
            runSampleToolBounded(outputURL: sampleURL)
        }

        prune(keeping: configuration.keepNewestFileCount)
        return reportURL
    }

    private func runSampleToolBounded(outputURL: URL) {
        guard configuration.flavour == .direct else {
            Self.logger.notice("skipped /usr/bin/sample (app store build)")
            return
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let runner = configuration.runSampleTool
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue(
            label: "com.notchflow.runaway-diagnostics.sample",
            qos: .utility
        ).async {
            runner(pid, outputURL)
            semaphore.signal()
        }
        let timeout = DispatchTime.now() + configuration.sampleWaitTimeoutSeconds
        if semaphore.wait(timeout: timeout) == .timedOut {
            Self.logger.error(
                "sample tool did not finish within \(self.configuration.sampleWaitTimeoutSeconds) s; continuing without it"
            )
        }
    }

    private func prune(keeping newestCount: Int) {
        let fileManager = FileManager.default
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: configuration.directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        else {
            return
        }
        let files = entries.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        let sortedByNewest = files.sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard sortedByNewest.count > newestCount else {
            return
        }
        let staleFiles = sortedByNewest.dropFirst(newestCount)
        for staleFile in staleFiles {
            try? fileManager.removeItem(at: staleFile)
        }
        Self.logger.notice("pruned \(staleFiles.count) stale diagnostics files")
    }

    private func writeAtomically(_ data: Data, to finalURL: URL) throws {
        let temporaryURL = finalURL.deletingLastPathComponent()
            .appendingPathComponent(".\(finalURL.lastPathComponent).tmp", isDirectory: false)
        let fileManager = FileManager.default
        try data.write(to: temporaryURL)
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: finalURL)
    }

    static func runSampleProcess(pid: pid_t, outputURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = [String(Int(pid)), "5", "-file", outputURL.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("failed to run /usr/bin/sample: \(error.localizedDescription)")
        }
    }

    private static func collectThreadRows() -> [ThreadRow] {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let listStatus = task_threads(mach_task_self_, &threadList, &threadCount)
        guard listStatus == KERN_SUCCESS, let list = threadList else {
            logger.error("task_threads failed: \(listStatus)")
            return []
        }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: list)),
                vm_size_t(MemoryLayout<thread_t>.stride) * vm_size_t(threadCount)
            )
        }
        guard threadCount > 0 else {
            return []
        }

        var rows: [ThreadRow] = []
        for index in 0..<Int(threadCount) {
            let thread = list[index]
            defer {
                mach_port_deallocate(mach_task_self_, thread)
            }

            var basicInfo = thread_basic_info()
            let basicStatus = withUnsafeMutablePointer(to: &basicInfo) { pointer in
                pointer.withMemoryRebound(
                    to: integer_t.self,
                    capacity: MemoryLayout<thread_basic_info>.stride / MemoryLayout<integer_t>.stride
                ) { integers in
                    var infoCount = mach_msg_type_number_t(
                        MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size
                    )
                    return thread_info(
                        thread,
                        thread_flavor_t(THREAD_BASIC_INFO),
                        integers,
                        &infoCount
                    )
                }
            }
            guard basicStatus == KERN_SUCCESS else {
                continue
            }

            var extendedInfo = thread_extended_info()
            let extendedStatus = withUnsafeMutablePointer(to: &extendedInfo) { pointer in
                pointer.withMemoryRebound(
                    to: integer_t.self,
                    capacity: MemoryLayout<thread_extended_info>.stride / MemoryLayout<integer_t>.stride
                ) { integers in
                    var infoCount = mach_msg_type_number_t(
                        MemoryLayout<thread_extended_info>.size / MemoryLayout<integer_t>.size
                    )
                    return thread_info(
                        thread,
                        thread_flavor_t(THREAD_EXTENDED_INFO),
                        integers,
                        &infoCount
                    )
                }
            }
            let threadName = extendedStatus == KERN_SUCCESS
                ? Self.threadName(from: extendedInfo)
                : "-"

            var identifierInfo = thread_identifier_info()
            let identifierStatus = withUnsafeMutablePointer(to: &identifierInfo) { pointer in
                pointer.withMemoryRebound(
                    to: integer_t.self,
                    capacity: MemoryLayout<thread_identifier_info>.stride / MemoryLayout<integer_t>.stride
                ) { integers in
                    var infoCount = mach_msg_type_number_t(
                        MemoryLayout<thread_identifier_info>.size / MemoryLayout<integer_t>.size
                    )
                    return thread_info(
                        thread,
                        thread_flavor_t(THREAD_IDENTIFIER_INFO),
                        integers,
                        &infoCount
                    )
                }
            }
            let threadID = identifierStatus == KERN_SUCCESS ? identifierInfo.thread_id : 0

            rows.append(
                ThreadRow(
                    cpuPercent: Double(basicInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0,
                    userSeconds: Self.seconds(from: basicInfo.user_time),
                    systemSeconds: Self.seconds(from: basicInfo.system_time),
                    threadID: threadID,
                    name: threadName
                )
            )
        }
        return rows.sorted { $0.cpuPercent > $1.cpuPercent }
    }

    private static func seconds(from timeValue: time_value_t) -> Double {
        Double(timeValue.seconds) + Double(timeValue.microseconds) / 1_000_000
    }

    private static func threadName(from extendedInfo: thread_extended_info) -> String {
        withUnsafeBytes(of: extendedInfo.pth_name) { rawBuffer in
            let characters = rawBuffer.bindMemory(to: CChar.self)
            let terminator = characters.firstIndex(of: 0) ?? characters.count
            let utf8Bytes = characters.prefix(terminator).map { UInt8(bitPattern: $0) }
            return String(decoding: utf8Bytes, as: UTF8.self)
        }
    }

    private static func fileStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func reportText(
        kind: ReportKind,
        cpuPercent: Double,
        sampleHistory: [CPUSample],
        transitions: [String],
        mainThreadResponsive: Bool,
        displayTarget: String,
        activityKinds: [String],
        reason: String?,
        writtenAt: Date,
        pid: pid_t,
        threadRows: [ThreadRow],
        sampleURL: URL?,
        flavour: BuildFlavour
    ) -> String {
        let stampFormatter = ISO8601DateFormatter()
        var lines: [String] = []

        lines.append("NotchFlow CPU diagnostics — \(kind.title)")
        lines.append(String(repeating: "=", count: 40))
        lines.append("written: \(stampFormatter.string(from: writtenAt))")
        lines.append("build flavour: \(flavour.rawValue)")
        lines.append("pid: \(Int(pid))")
        if let reason {
            lines.append("reason: \(reason)")
        }
        lines.append("process cpu: \(String(format: "%.1f", cpuPercent))% of one core")
        lines.append("main thread responsive: \(mainThreadResponsive ? "yes" : "no")")
        lines.append("display target: \(displayTarget)")
        lines.append("active activity kinds: \(activityKinds.joined(separator: ", "))")

        lines.append("")
        lines.append("sample history (\(sampleHistory.count) samples, age relative to newest):")
        if sampleHistory.isEmpty {
            lines.append("  (none)")
        } else {
            lines.append("  age_s   cpu%  main")
            let newest = sampleHistory.map(\.at).max()!
            for sample in sampleHistory {
                let age = newest - sample.at
                lines.append(
                    String(
                        format: "  %5.0f  %5.1f  %@",
                        Double(age.components.seconds),
                        sample.cpuPercent,
                        sample.mainThreadResponsive ? "yes" : "no"
                    )
                )
            }
        }

        lines.append("")
        lines.append("state transitions (\(transitions.count)):")
        if transitions.isEmpty {
            lines.append("  (none)")
        } else {
            for transition in transitions {
                lines.append("  \(transition)")
            }
        }

        if kind == .alarm {
            lines.append("")
            lines.append("per-thread CPU (\(threadRows.count) threads, sorted by cpu, percent of one core):")
            lines.append("    cpu%   user_s   sys_s         tid  name")
            if threadRows.isEmpty {
                lines.append("  (unavailable)")
            } else {
                for row in threadRows {
                    lines.append(
                        String(
                            format: "  %6.1f  %7.1f  %7.1f  %10llu  %@",
                            row.cpuPercent,
                            row.userSeconds,
                            row.systemSeconds,
                            row.threadID,
                            row.name.isEmpty ? "-" : row.name
                        )
                    )
                }
            }

            lines.append("")
            if let sampleURL, flavour == .direct {
                lines.append("/usr/bin/sample output: \(sampleURL.path)")
            } else {
                lines.append("/usr/bin/sample output: skipped (app store build)")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }
}
