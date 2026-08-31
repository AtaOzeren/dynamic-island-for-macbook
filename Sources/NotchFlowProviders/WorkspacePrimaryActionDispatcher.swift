import AppKit
import Foundation
import NotchFlowCore

/// Executes a `PrimaryAction.Intent` that acts on the wider system.
///
/// Timer intents are deliberately absent: they are routing, not system calls —
/// the composition root sends them to `TimerProvider.handle(_:)` exactly as the
/// timer view's own controls do, and a second execution path would be a second
/// chance for the two to disagree about what a pause means.
@MainActor
public protocol PrimaryActionDispatching: AnyObject {
    /// Performs the intent. Returns whether something was activated — `false`
    /// means the target is not running and no installed application matched,
    /// which the caller may surface rather than swallow.
    @discardableResult
    func perform(_ intent: PrimaryAction.Intent) -> Bool
}

/// The production executor: activates an application through `NSWorkspace`.
///
/// Resolution is by running application first and by known bundle identifier
/// second. Name-first is what makes the music case honest — the activity
/// carries the source name the system itself reported — while bundle-id
/// fallback covers the target not running yet, which is exactly when an "open"
/// affordance earns its title.
@MainActor
public final class WorkspacePrimaryActionDispatcher: PrimaryActionDispatching {
    /// Where a name lookup has to become a bundle identifier. Only the players
    /// the app actually names in activities belong here; an unknown name has
    /// no entry and the intent resolves to a handled failure.
    private static let bundleIdentifiersByName = [
        "Spotify": "com.spotify.client",
        "Music": "com.apple.Music",
        "Apple Music": "com.apple.Music",
        "Claude": "com.anthropic.claudefordesktop",
        "Claude Code": "com.anthropic.claudefordesktop",
        "Codex": "com.openai.chat",
        "OpenCode": "dev.opencode.app",
    ]

    public init() {}

    public func perform(_ intent: PrimaryAction.Intent) -> Bool {
        switch intent {
        case .openApplicationNamed(let name):
            return activateApplication(named: name)
        case .openAgentApplication(let agent):
            return activateApplication(named: agent.displayName)
        case .stopTimer, .pauseTimer, .resumeTimer:
            return false
        }
    }

    private func activateApplication(named name: String) -> Bool {
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == name && $0.activationPolicy == .regular
        }) {
            return running.activate()
        }

        guard
            let bundleIdentifier = Self.bundleIdentifiersByName[name],
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            return false
        }
        // The synchronous `open(_:)` rather than the async `openApplication`:
        // the click's result must be knowable at the call site, and launching
        // an app URL is the one operation `open` answers honestly with a Bool.
        return NSWorkspace.shared.open(url)
    }
}
