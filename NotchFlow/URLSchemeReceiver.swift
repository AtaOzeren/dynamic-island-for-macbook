import AppKit
import Foundation
import NotchFlowCore

/// Receives `notchflow://` URLs for an app that usually has no window open.
///
/// SwiftUI's `onOpenURL` is a view modifier, so it only listens once the scene
/// it is attached to has instantiated its content. NotchFlow's only scenes are
/// `Settings` and the status item's menu, and neither exists until the user
/// opens it — which would make every hook message dropped on the floor except
/// in the rare moment the settings window happens to be on screen. The
/// application delegate receives the same URLs with no window at all.
@MainActor
final class URLSchemeAppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the composition root. Static because `NSApplicationDelegateAdaptor`
    /// constructs the delegate itself and hands back no seam to inject through;
    /// the app is a single instance, so there is exactly one writer.
    nonisolated(unsafe) static var onOpenURL: (@MainActor (URL) -> Void)?

    /// Runs before the process exits, for the resources that must be released
    /// rather than merely abandoned — currently the loopback listener's socket.
    /// Set by the composition root, for the same reason `onOpenURL` is.
    nonisolated(unsafe) static var onTerminate: (@MainActor () -> Void)?

    nonisolated func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls {
                Self.onOpenURL?(url)
            }
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            Self.onTerminate?()
        }
    }
}

@MainActor
final class URLSchemeReceiver {
    var onMessage: ((IPCMessage) -> Void)?

    /// The same gate the loopback listener applies, because the URL scheme is
    /// the transport every installed hook actually uses — leaving it ungated
    /// would make each toggle a no-op for real agents.
    var preferences: AIIntegrationPreferences

    init(
        preferences: AIIntegrationPreferences = .default,
        onMessage: ((IPCMessage) -> Void)? = nil
    ) {
        self.preferences = preferences
        self.onMessage = onMessage
    }

    func handle(_ url: URL) {
        guard let message = try? IPCURLParser().parse(url),
            preferences.allows(message)
        else {
            return
        }
        onMessage?(message)
    }
}
