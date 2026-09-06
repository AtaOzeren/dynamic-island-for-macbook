import Foundation

/// Shared ISO-8601 encoding for the watchdog's on-disk state. The ledger and
/// the event marker must agree on the format: a report written by one build
/// is read back by the next launch, so the representation is part of the
/// file contract rather than an implementation detail of either type.
enum ISO8601Timestamp {
    private static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    static func string(from date: Date) -> String {
        makeFormatter().string(from: date)
    }

    static func date(from string: String) -> Date? {
        makeFormatter().date(from: string)
    }
}
