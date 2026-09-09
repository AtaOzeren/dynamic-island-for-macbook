import Foundation
import os

/// Hands one watchdog event across a relaunch so the next launch can tell
/// the user why the app restarted or quit.
///
/// The marker is consumed on read: `consume()` deletes the file in the same
/// call that decodes it, so the post-launch notice cannot fire twice even if
/// two code paths ask for it. A corrupt file is deleted too — an
/// undecodable marker is stale state, and leaving it behind would surface
/// the same failure on every subsequent launch.
public struct WatchdogEventMarker: Sendable {
    public enum Action: String, Codable, Sendable {
        case relaunch
        case quit
    }

    public struct Event: Equatable, Sendable {
        public let action: Action
        public let reason: String
        public let at: Date
        public let reportPath: String?

        public init(action: Action, reason: String, at: Date, reportPath: String?) {
            self.action = action
            self.reason = reason
            self.at = at
            self.reportPath = reportPath
        }
    }

    private struct Payload: Codable {
        let action: Action
        let reason: String
        let at: String
        let reportPath: String?
    }

    private static let logger = Logger(
        subsystem: "com.kernotch.KerNotch",
        category: "WatchdogEventMarker"
    )
    private static let fileName = "cpu-watchdog-last-event.json"

    public let fileURL: URL

    private let directoryURL: URL

    public init(directoryURL: URL? = nil) {
        let resolvedDirectory = directoryURL ?? ApplicationDirectories.applicationSupport
        self.directoryURL = resolvedDirectory
        fileURL = resolvedDirectory.appendingPathComponent(Self.fileName, isDirectory: false)
    }

    public func write(_ event: Event) {
        let payload = Payload(
            action: event.action,
            reason: event.reason,
            at: ISO8601Timestamp.string(from: event.at),
            reportPath: event.reportPath
        )
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to write watchdog marker: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func consume() -> Event? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        guard
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            let at = ISO8601Timestamp.date(from: payload.at)
        else {
            Self.logger.error("Discarding corrupt watchdog marker at \(self.fileURL.path, privacy: .public)")
            return nil
        }
        return Event(
            action: payload.action,
            reason: payload.reason,
            at: at,
            reportPath: payload.reportPath
        )
    }
}
