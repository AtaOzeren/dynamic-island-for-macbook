import Foundation
import NotchFlowCore

/// One player's answer about what it is playing right now.
///
/// A stopped player has no snapshot rather than a snapshot describing silence,
/// which is what lets the three ways a player can fail to answer — not running,
/// Automation permission denied, stopped — collapse into one absent value that
/// the provider handles identically. That collapse is the acceptance criterion
/// "denying Automation permission degrades silently", implemented as a type
/// rather than as a rule to remember.
public struct MusicPlayerSnapshot: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let playbackState: MusicPlaybackState

    public init(title: String, artist: String, playbackState: MusicPlaybackState) {
        self.title = title
        self.artist = artist
        self.playbackState = playbackState
    }
}

/// The seam between "however we ask a player what it is playing" and the
/// selection, deduplication and teardown logic over the answers.
///
/// Split out for the reason `docs/06-activity-providers.md` gives: the
/// ScriptingBridge round-trip and the Apple Events consent prompt can only be
/// exercised on real hardware with those apps installed, while everything the
/// provider decides on top of the answers must be verifiable in CI against a
/// fake. Conformances answer synchronously and never block on launching an app.
@MainActor
public protocol MusicPlayerQuerying: AnyObject {
    /// The player's current state, or `nil` if it is not running, is not
    /// playing, or refused to answer.
    func snapshot(for target: MusicPlayerTarget) -> MusicPlayerSnapshot?

    /// Best-effort transport. A target that cannot honour the command drops it.
    func send(_ command: MusicTransportCommand, to target: MusicPlayerTarget)
}

/// The App Store build's music backend: ScriptingBridge against Spotify and
/// Music.app, woken by the distributed notifications those apps post.
///
/// Nothing here polls, per `docs/06-activity-providers.md`: the provider holds
/// no timer and reads no player state until a notification arrives, so a machine
/// with both apps closed costs exactly two notification subscriptions and no
/// wakeups at all.
///
/// Its one piece of judgement is refusing to speak when nothing changed. Both
/// apps post more often than their user-visible state changes, and
/// `ActivityManager` restarts the dismiss window on each update, so a provider
/// that forwarded every callback would pin the island open — the same reasoning
/// `ChargingProvider` documents, reached from a different source.
@MainActor
public final class AppleScriptMusicProvider: MusicProvider {
    private let players: any MusicPlayerQuerying
    private let notifications: NotificationCenter
    private let subscriptions = NotificationSubscriptionBag()
    private var observer: NowPlayingObserver?
    private var reported: Reported?

    /// What was last emitted, plus which player it came from. The target is
    /// carried alongside the emission rather than tracked separately because
    /// transport has to reach the app the user can currently see: they are one
    /// fact, so they cannot drift apart.
    private struct Reported: Equatable {
        let nowPlaying: NowPlaying
        let target: MusicPlayerTarget
    }

    /// The gate is a parameter rather than a detail of the client because the
    /// settings pane has to read and drive the very same permission state the
    /// provider is gated on. Two gates would let the pane offer a prompt for a
    /// target the provider had already recorded as explained, which is the
    /// double-ask the permission flow forbids.
    public convenience init(gate: MusicAutomationGate = MusicAutomationGate()) {
        self.init(
            players: ScriptingBridgeMusicPlayerClient(gate: gate),
            notifications: DistributedNotificationCenter.default()
        )
    }

    init(players: any MusicPlayerQuerying, notifications: NotificationCenter) {
        self.players = players
        self.notifications = notifications
    }

    public var backendName: String { "ScriptingBridge" }

    public func startObserving(_ observer: @escaping NowPlayingObserver) {
        stopObserving()
        self.observer = observer

        for target in MusicPlayerTarget.allCases {
            let token = notifications.addObserver(
                forName: target.playbackNotificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(wokenBy: target) }
            }
            subscriptions.add(token, to: notifications)
        }
    }

    /// Forgetting the last emission is part of stopping: a provider restarted
    /// while the same track is still playing must report it rather than dedupe
    /// against a reading from before anyone was listening.
    public func stopObserving() {
        subscriptions.removeAll()
        observer = nil
        reported = nil
    }

    /// Transport goes to the player being reported, not to whichever app
    /// answered most recently — the island shows one track, and its buttons
    /// have to control that one. With nothing reported there is no honest
    /// target, so the command is dropped rather than guessed at.
    public func send(_ command: MusicTransportCommand) {
        guard let reported else { return }
        players.send(command, to: reported.target)
    }

    /// Both targets are re-read on either app's notification. The posting app
    /// only says that *it* changed, and the island reports one track across
    /// both, so a Music.app pause is exactly when Spotify's state has to be
    /// re-checked rather than the moment to trust a stale reading.
    private func refresh(wokenBy target: MusicPlayerTarget) {
        let reported = Self.reported(from: snapshots(preferring: target))
        guard self.reported != reported else { return }
        self.reported = reported
        observer?(reported?.nowPlaying)
    }

    /// The waking player is read first so it wins a tie against an equally
    /// playing rival: with no better answer available, "the one that just
    /// spoke" is what keeps the island from flapping between two paused
    /// players every time either posts.
    private func snapshots(
        preferring target: MusicPlayerTarget
    ) -> [(target: MusicPlayerTarget, snapshot: MusicPlayerSnapshot)] {
        let ordered = [target] + MusicPlayerTarget.allCases.filter { $0 != target }
        return ordered.compactMap { candidate in
            players.snapshot(for: candidate).map { (candidate, $0) }
        }
    }

    /// A playing player outranks a paused one, because a paused player is
    /// something the user left behind while a playing one is what they are
    /// listening to now. No player at all is silence, which is teardown rather
    /// than an activity describing absence.
    private static func reported(
        from candidates: [(target: MusicPlayerTarget, snapshot: MusicPlayerSnapshot)]
    ) -> Reported? {
        let best = candidates.first { $0.snapshot.playbackState == .playing } ?? candidates.first
        guard let best else { return nil }

        return Reported(
            nowPlaying: NowPlaying(
                title: best.snapshot.title,
                artist: best.snapshot.artist,
                playbackState: best.snapshot.playbackState,
                sourceApplicationName: best.target.displayName
            ),
            target: best.target
        )
    }
}
