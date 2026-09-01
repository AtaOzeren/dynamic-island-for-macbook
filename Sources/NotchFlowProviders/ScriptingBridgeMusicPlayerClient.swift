import AppKit
import Foundation
import NotchFlowCore
import ScriptingBridge

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
            let rawState = (player.value(forKey: "playerState") as? NSNumber)?.intValue,
            let playbackState = Self.playbackState(rawState),
            let track = player.value(forKey: "currentTrack") as? SBObject,
            let title = track.value(forKey: "name") as? String,
            title.isEmpty == false
        else { return nil }

        return MusicPlayerSnapshot(
            title: title,
            artist: track.value(forKey: "artist") as? String ?? "",
            playbackState: playbackState,
            artworkData: Self.artworkData(from: track, target: target),
            artworkURL: Self.artworkURL(from: track, target: target)
        )
    }

    func send(_ command: MusicTransportCommand, to target: MusicPlayerTarget) {
        guard let player = player(for: target) else { return }

        let selectorName: String
        switch command {
        case .previousTrack: selectorName = "previousTrack"
        case .playPause: selectorName = "playpause"
        case .nextTrack: selectorName = "nextTrack"
        }
        player.perform(NSSelectorFromString(selectorName))
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
    private func player(for target: MusicPlayerTarget) -> SBApplication? {
        guard runningBundleIdentifiers().contains(target.bundleIdentifier) else { return nil }
        guard gate.canQuery(target) else { return nil }

        if let cached = applications[target] {
            return cached
        }

        guard let application = SBApplication(bundleIdentifier: target.bundleIdentifier) else { return nil }
        application.delegate = errorSuppressor
        applications[target] = application
        return application
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

    private static func artworkURL(from track: SBObject, target: MusicPlayerTarget) -> URL? {
        guard target == .spotify else { return nil }
        guard
            let value = (track.value(forKey: "artworkUrl") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            value.isEmpty == false
        else { return nil }
        return URL(string: value)
    }

    private static func artworkData(from track: SBObject, target: MusicPlayerTarget) -> Data? {
        guard target == .appleMusic else { return nil }
        guard
            let artworks = track.value(forKey: "artworks") as? SBElementArray,
            let artwork = artworks.firstObject as? SBObject,
            let image = artwork.value(forKey: "data") as? NSImage,
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }

        return bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
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
