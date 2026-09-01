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
    public let artworkData: Data?
    public let artworkURL: URL?

    public init(
        title: String,
        artist: String,
        playbackState: MusicPlaybackState,
        artworkData: Data? = nil,
        artworkURL: URL? = nil
    ) {
        self.title = title
        self.artist = artist
        self.playbackState = playbackState
        self.artworkData = artworkData
        self.artworkURL = artworkURL
    }
}

public protocol ArtworkDataLoading: Sendable {
    func data(from url: URL) async -> Data?
}

public actor URLSessionArtworkDataLoader: ArtworkDataLoading {
    private let session: URLSession
    private var cachedData: [URL: Data] = [:]
    private var failedURLs: Set<URL> = []

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(from url: URL) async -> Data? {
        guard url.scheme?.lowercased() == "https" else { return nil }
        if let data = cachedData[url] { return data }
        guard failedURLs.contains(url) == false else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard
                let response = response as? HTTPURLResponse,
                (200..<300).contains(response.statusCode),
                response.mimeType?.hasPrefix("image/") == true,
                data.isEmpty == false,
                data.count <= NowPlaying.maximumArtworkByteCount
            else {
                failedURLs.insert(url)
                return nil
            }
            cachedData[url] = data
            return data
        } catch {
            failedURLs.insert(url)
            return nil
        }
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
    private let artworkLoader: (any ArtworkDataLoading)?
    private let subscriptions = NotificationSubscriptionBag()
    private var observer: NowPlayingObserver?
    private var reported: Reported?
    private var artworkTask: Task<Void, Never>?
    private var loadingArtwork: ArtworkIdentity?

    /// What was last emitted, plus which player it came from. The target is
    /// carried alongside the emission rather than tracked separately because
    /// transport has to reach the app the user can currently see: they are one
    /// fact, so they cannot drift apart.
    private struct Reported: Equatable {
        let nowPlaying: NowPlaying
        let target: MusicPlayerTarget
        let artworkURL: URL?

        var artworkIdentity: ArtworkIdentity? {
            artworkURL.map {
                ArtworkIdentity(
                    target: target,
                    title: nowPlaying.title,
                    artist: nowPlaying.artist,
                    url: $0
                )
            }
        }

        func carryingArtwork(from current: Reported?) -> Self {
            guard
                let current,
                artworkIdentity == current.artworkIdentity,
                nowPlaying.artworkData == nil,
                let artworkData = current.nowPlaying.artworkData
            else { return self }

            return Reported(
                nowPlaying: nowPlaying.withArtworkData(artworkData),
                target: target,
                artworkURL: artworkURL
            )
        }

        func withArtworkData(_ artworkData: Data) -> Self {
            Reported(
                nowPlaying: nowPlaying.withArtworkData(artworkData),
                target: target,
                artworkURL: artworkURL
            )
        }
    }

    private struct ArtworkIdentity: Equatable {
        let target: MusicPlayerTarget
        let title: String
        let artist: String
        let url: URL
    }

    /// The gate is a parameter rather than a detail of the client because the
    /// settings pane has to read and drive the very same permission state the
    /// provider is gated on. Two gates would let the pane offer a prompt for a
    /// target the provider had already recorded as explained, which is the
    /// double-ask the permission flow forbids.
    public convenience init(
        gate: MusicAutomationGate = MusicAutomationGate(),
        artworkLoader: (any ArtworkDataLoading)? = nil
    ) {
        self.init(
            players: ScriptingBridgeMusicPlayerClient(gate: gate),
            notifications: DistributedNotificationCenter.default(),
            artworkLoader: artworkLoader
        )
    }

    init(
        players: any MusicPlayerQuerying,
        notifications: NotificationCenter,
        artworkLoader: (any ArtworkDataLoading)? = nil
    ) {
        self.players = players
        self.notifications = notifications
        self.artworkLoader = artworkLoader
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

        // A notification only ever reports a *change*, so a track already
        // playing when observation starts posts nothing. Without this first
        // read the island stays empty until the user changes track.
        refresh(wokenBy: nil)
    }

    /// Forgetting the last emission is part of stopping: a provider restarted
    /// while the same track is still playing must report it rather than dedupe
    /// against a reading from before anyone was listening.
    public func stopObserving() {
        subscriptions.removeAll()
        artworkTask?.cancel()
        artworkTask = nil
        loadingArtwork = nil
        observer = nil
        reported = nil
    }

    /// Re-reads both players after a user grants Automation access. The grant
    /// itself does not produce a playback notification, so waiting for one can
    /// leave an already-playing Music track invisible until its next change.
    public func refreshCurrentState() {
        guard observer != nil else { return }
        refresh(wokenBy: nil)
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
    private func refresh(wokenBy target: MusicPlayerTarget?) {
        let next = Self.reported(from: snapshots(preferring: target))
            .map { $0.carryingArtwork(from: reported) }
        guard reported != next else { return }
        reported = next
        observer?(next?.nowPlaying)
        loadArtworkIfNeeded(for: next)
    }

    private func loadArtworkIfNeeded(for reported: Reported?) {
        guard
            let reported,
            reported.nowPlaying.artworkData == nil,
            let identity = reported.artworkIdentity,
            let artworkLoader
        else {
            artworkTask?.cancel()
            artworkTask = nil
            loadingArtwork = nil
            return
        }
        guard loadingArtwork != identity else { return }

        artworkTask?.cancel()
        loadingArtwork = identity
        artworkTask = Task { @MainActor [weak self] in
            let artworkData = await artworkLoader.data(from: identity.url)
            guard Task.isCancelled == false, let self else { return }
            guard loadingArtwork == identity else { return }
            loadingArtwork = nil
            artworkTask = nil
            guard
                let artworkData,
                let current = self.reported,
                current.artworkIdentity == identity
            else { return }

            let updated = current.withArtworkData(artworkData)
            guard updated.nowPlaying.artworkData != nil, updated != current else { return }
            self.reported = updated
            observer?(updated.nowPlaying)
        }
    }

    /// The waking player is read first so it wins a tie against an equally
    /// playing rival: with no better answer available, "the one that just
    /// spoke" is what keeps the island from flapping between two paused
    /// players every time either posts. `nil` is the start-up read, where no
    /// player has spoken and declaration order breaks the tie instead.
    private func snapshots(
        preferring target: MusicPlayerTarget?
    ) -> [(target: MusicPlayerTarget, snapshot: MusicPlayerSnapshot)] {
        let ordered =
            target.map { waking in
                [waking] + MusicPlayerTarget.allCases.filter { $0 != waking }
            } ?? MusicPlayerTarget.allCases
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
            ).withArtworkData(best.snapshot.artworkData),
            target: best.target,
            artworkURL: best.snapshot.artworkURL
        )
    }
}
