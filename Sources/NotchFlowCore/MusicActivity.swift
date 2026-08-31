import Foundation

/// Whether the current track is advancing. There is deliberately no `stopped`
/// case: a stopped player produces no activity at all rather than an activity
/// describing silence, per the teardown rule in `docs/06-activity-providers.md`.
public enum MusicPlaybackState: Equatable, Sendable {
    case playing
    case paused
}

/// A transport control the island offers. The command is a value, not a closure,
/// so the compact and expanded views can be asserted on without a live backend;
/// `MusicProvider` in `NotchFlowProviders` is what actually sends one.
public enum MusicTransportCommand: CaseIterable, Equatable, Sendable {
    case previousTrack
    case playPause
    case nextTrack
}

/// The now-playing metadata both music backends produce, and the only music
/// vocabulary above `NotchFlowProviders`.
///
/// Nothing here names either backend's framework, which is the point:
/// `docs/06-activity-providers.md` requires the two backends to be
/// interchangeable, so any type carrying a backend's fingerprint would leak that
/// choice into the view layer.
public struct NowPlaying: Equatable, Sendable {
    /// Track metadata comes from whatever app happens to be playing, so it is
    /// untrusted input in the same sense as an IPC payload: bounded on the way
    /// in rather than trusted and truncated at draw time.
    public static let maximumFieldLength = 200

    public let title: String
    public let artist: String
    public let playbackState: MusicPlaybackState
    /// The human-readable name of the app the audio is coming from, when the
    /// backend can attribute it. The Direct build's system-wide observation
    /// cannot always name a source, so this stays optional.
    public let sourceApplicationName: String?

    public init(
        title: String,
        artist: String,
        playbackState: MusicPlaybackState,
        sourceApplicationName: String? = nil
    ) {
        self.title = Self.sanitized(title) ?? ""
        self.artist = Self.sanitized(artist) ?? ""
        self.playbackState = playbackState
        self.sourceApplicationName = Self.sanitized(sourceApplicationName)
    }

    private static func sanitized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            trimmed.isEmpty == false
        else {
            return nil
        }

        return String(trimmed.prefix(maximumFieldLength))
    }
}

/// The single music activity, whichever backend supplies it.
public struct MusicActivity: Activity, Equatable {
    /// One identity for all music, for the lifetime of the app.
    ///
    /// A track change is an update to the same activity, not a new one — which
    /// is what keeps the island from re-sorting itself every few minutes, since
    /// `ActivityManager.register` preserves the first registration time for an
    /// identity it already holds.
    public static let identity = ActivityIdentity("notchflow.music")

    public let nowPlaying: NowPlaying

    public init(nowPlaying: NowPlaying) {
        self.nowPlaying = nowPlaying
    }

    public var identity: ActivityIdentity { Self.identity }

    public var kind: ActivityKind { .music }

    /// `low`, per the V1 priority table in `docs/05-activity-model.md`: music
    /// never forces the panel visible on its own account.
    public var priority: ActivityPriority { .low }

    /// Music ends when the player stops, never on a clock.
    public var autoDismiss: AutoDismissDescriptor? { nil }

    public var primaryAction: PrimaryAction? {
        guard let source = nowPlaying.sourceApplicationName else { return nil }
        return PrimaryAction(title: localized("Open \(source)"), symbolName: "arrow.up.forward")
    }
}
