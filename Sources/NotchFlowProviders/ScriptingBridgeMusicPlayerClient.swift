import AppKit
import Foundation
import NotchFlowCore
import ScriptingBridge

/// The scripting interface both target apps expose. One protocol serves both
/// because their `.sdef`s agree on every term NotchFlow uses — the track's
/// `name` and `artist`, the four-char `playerState`, and the four transport
/// commands — so the difference between the two apps is the bundle identifier
/// and nothing else.
///
/// Every member is `optional` because ScriptingBridge answers through a proxy:
/// an app that is not running, is an older version, or has refused the Apple
/// Event simply does not respond, and an optional requirement turns that into
/// `nil` instead of a trap.
@objc private protocol ScriptingBridgeTrack {
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
}

@objc private protocol ScriptingBridgePlayer {
    @objc optional var playerState: Int { get }
    @objc optional var currentTrack: ScriptingBridgeTrack { get }
    @objc optional func playpause()
    @objc optional func nextTrack()
    @objc optional func previousTrack()
}

/// Asks Spotify and Music.app what they are playing, and relays transport back.
///
/// This is the half of the App Store music backend that cannot run in CI: it
/// needs the two apps installed and the Apple Events consent granted, so the
/// logic worth testing lives above the `MusicPlayerQuerying` seam and this type
/// stays as thin as the round-trip allows.
///
/// Two rules shape it. It never launches anything: a target with no running
/// instance is answered from `NSWorkspace` without a single Apple Event, so
/// opening NotchFlow cannot start iTunes the way a naive `SBApplication` send
/// would. And it never throws: a refused or failed event returns `nil` through
/// the delegate below, which is what makes "denying Automation permission
/// degrades silently" a property of the code rather than a promise.
@MainActor
final class ScriptingBridgeMusicPlayerClient: MusicPlayerQuerying {
    /// The `.sdef` player-state constants, identical in both apps. Only
    /// `playing` and `paused` are named: every other value, `stopped`
    /// included, is the absence of a snapshot.
    private static let playingState = fourCharCode("kPSP")
    private static let pausedState = fourCharCode("kPSp")

    private let runningBundleIdentifiers: () -> Set<String>
    private let gate: MusicAutomationGate
    private let errorSuppressor = ScriptingBridgeErrorSuppressor()
    private var applications: [MusicPlayerTarget: SBApplication] = [:]

    init(
        gate: MusicAutomationGate = MusicAutomationGate(),
        runningBundleIdentifiers: @escaping () -> Set<String> = {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
    ) {
        self.gate = gate
        self.runningBundleIdentifiers = runningBundleIdentifiers
    }

    func snapshot(for target: MusicPlayerTarget) -> MusicPlayerSnapshot? {
        guard
            let player = player(for: target),
            let playbackState = Self.playbackState(player.playerState),
            let track = player.currentTrack,
            let title = track.name,
            title.isEmpty == false
        else {
            return nil
        }

        return MusicPlayerSnapshot(
            title: title,
            artist: track.artist ?? "",
            playbackState: playbackState
        )
    }

    func send(_ command: MusicTransportCommand, to target: MusicPlayerTarget) {
        guard let player = player(for: target) else { return }

        switch command {
        case .previousTrack: player.previousTrack?()
        case .playPause: player.playpause?()
        case .nextTrack: player.nextTrack?()
        }
    }

    /// Proxies are cached because building one is the expensive half of the
    /// round-trip and the app it points at outlives any single notification.
    /// The running check is repeated on every call regardless, so a cached
    /// proxy to a quit app answers `nil` rather than relaunching it.
    ///
    /// The gate is consulted after the running check and before the proxy,
    /// because this is the last point where "no Apple Event is sent" is still
    /// true: an unpermitted target has to answer `nil` from here, which the
    /// snapshot path already reads as "not playing" and the transport path as a
    /// dropped command. That is where the permission flow's graceful degradation
    /// actually happens.
    private func player(for target: MusicPlayerTarget) -> ScriptingBridgePlayer? {
        guard runningBundleIdentifiers().contains(target.bundleIdentifier) else { return nil }
        guard gate.canQuery(target) else { return nil }

        if let cached = applications[target] {
            return cached as? ScriptingBridgePlayer
        }

        guard let application = SBApplication(bundleIdentifier: target.bundleIdentifier) else { return nil }
        application.delegate = errorSuppressor
        applications[target] = application
        return application as? ScriptingBridgePlayer
    }

    /// A stopped player has no snapshot, per the teardown rule in
    /// `docs/06-activity-providers.md`, which is why this is optional rather
    /// than defaulting an unrecognised state to paused.
    private static func playbackState(_ rawValue: Int?) -> MusicPlaybackState? {
        switch rawValue {
        case playingState: .playing
        case pausedState: .paused
        default: nil
        }
    }

    private static func fourCharCode(_ code: String) -> Int {
        code.unicodeScalars.reduce(into: 0) { result, scalar in
            result = result << 8 + Int(scalar.value)
        }
    }
}

/// Turns a failed Apple Event into `nil` instead of an exception.
///
/// Without a delegate, ScriptingBridge reports a refused or failed event by
/// raising, and the one failure that matters here is routine: the user declining
/// the Automation prompt, or revoking it later in System Settings. Swallowing it
/// is the whole of "degrades silently" — a music activity is never worth an
/// alert, and the provider above already treats an unanswered player as one that
/// is not playing.
private final class ScriptingBridgeErrorSuppressor: NSObject, SBApplicationDelegate {
    func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: any Error) -> Any? {
        nil
    }
}
