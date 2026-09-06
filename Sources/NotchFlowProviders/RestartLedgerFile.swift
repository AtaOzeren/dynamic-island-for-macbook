import Foundation
import NotchFlowCore
import os

/// Durable restart ledger backing `CPUWatchdog`'s restart-loop guard.
///
/// The supervisor records a restart and then calls `exit()` within
/// milliseconds, so the store has to be a file written atomically: a
/// `UserDefaults` write is handed to `cfprefsd` and is not guaranteed to
/// reach disk before the process dies, which would let a crash loop restart
/// forever.
///
/// Instant-to-date bridge: `ContinuousClock.Instant` has no wall-clock
/// representation and does not survive a process restart, yet the ledger
/// must be comparable across launches. The ledger therefore captures one
/// anchor pair at construction — `referenceInstant` and the wall-clock
/// `Date` from `now()` naming the same moment — and maps any instant with
/// `date = referenceDate + referenceInstant.duration(to: instant)`. Both
/// clocks advance at the same rate while the process lives, so within a
/// launch the mapping is exact; across launches only the stored dates are
/// compared, which is what the one-hour window needs.
public final class RestartLedgerFile: RestartLedger {
    private static let logger = Logger(
        subsystem: "com.notchflow.NotchFlow",
        category: "RestartLedgerFile"
    )
    private static let fileName = "cpu-watchdog-restarts.json"

    public let fileURL: URL

    private let directoryURL: URL
    private let window: Duration
    private let referenceInstant: ContinuousClock.Instant
    private let referenceDate: Date

    public init(
        directoryURL: URL? = nil,
        window: Duration = .seconds(3600),
        referenceInstant: ContinuousClock.Instant = ContinuousClock().now,
        now: @Sendable () -> Date = { Date() }
    ) {
        let resolvedDirectory = directoryURL ?? ApplicationDirectories.applicationSupport
        self.directoryURL = resolvedDirectory
        self.window = window
        self.referenceInstant = referenceInstant
        referenceDate = now()
        fileURL = resolvedDirectory.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    public func recordRestart(at date: ContinuousClock.Instant) {
        let recordedAt = wallClockDate(for: date)
        let cutoff = wallClockDate(for: date.advanced(by: .zero - window))
        let retained = (storedDates() + [recordedAt])
            .filter { $0 >= cutoff }
            .sorted()
        write(retained)
    }

    public func restarts(since date: ContinuousClock.Instant) -> Int {
        let cutoff = wallClockDate(for: date)
        return storedDates().count { $0 >= cutoff }
    }

    private func wallClockDate(for instant: ContinuousClock.Instant) -> Date {
        referenceDate.addingTimeInterval(referenceInstant.duration(to: instant).seconds)
    }

    /// A missing, unreadable or corrupt ledger means "no known restarts":
    /// the guard must never block a legitimate restart because of a bad file.
    private func storedDates() -> [Date] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let timestamps = try? JSONDecoder().decode([String].self, from: data) else {
            Self.logger.error("Discarding corrupt restart ledger at \(self.fileURL.path, privacy: .public)")
            return []
        }
        return timestamps.compactMap(ISO8601Timestamp.date(from:))
    }

    private func write(_ dates: [Date]) {
        let timestamps = dates.map(ISO8601Timestamp.string(from:))
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(timestamps)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to write restart ledger: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension Duration {
    fileprivate var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
