import AppKit
import Foundation
import NotchFlowCore

/// Receives `notchflow://` URLs for an app that usually has no window open.
///
/// SwiftUI's `onOpenURL` is a view modifier, so it only listens once the scene
/// it is attached to has instantiated its content. NotchFlow has no persistent
/// ordinary window, so using that modifier would make hook delivery depend on
/// scene presentation. The application delegate receives the same URLs with no
/// window at all.
@MainActor
final class URLSchemeAppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the composition root. Static because `NSApplicationDelegateAdaptor`
    /// constructs the delegate itself and hands back no seam to inject through;
    /// the app is a single instance, so there is exactly one writer.
    nonisolated(unsafe) static var onOpenURL: (@MainActor (URL) -> Void)?

    /// Reopens Settings when Finder or Launch Services opens the already-running
    /// accessory app. With no Dock icon or ordinary window, the default reopen
    /// response has nothing it can bring forward.
    nonisolated(unsafe) static var onReopen: (@MainActor () -> Void)?

    /// Runs before the process exits, for the resources that must be released
    /// rather than merely abandoned — currently the loopback listener's socket.
    /// Set by the composition root, for the same reason `onOpenURL` is.
    nonisolated(unsafe) static var onTerminate: (@MainActor () -> Void)?

    /// Runs once AppKit has finished launching.
    ///
    /// Everything that needs a laid-out screen belongs here rather than in a
    /// `DispatchQueue.main.async` from the composition root's initialiser. That
    /// hop only waits for the next turn of the run loop, which can still come
    /// before AppKit knows the display arrangement — and a status item created
    /// then is placed at coordinates belonging to no screen's menu bar and is
    /// never re-laid-out, so it reports itself visible while nothing is drawn.
    nonisolated(unsafe) static var onDidFinishLaunching: (@MainActor () -> Void)? {
        didSet {
            guard hasFinishedLaunching else { return }
            MainActor.assumeIsolated { runDidFinishLaunching() }
        }
    }

    /// Whether launch already happened.
    ///
    /// The composition root sets `onDidFinishLaunching` from `App.init()`, which
    /// runs first — but a latch costs nothing and turns "first" from an ordering
    /// assumption into a fact the code enforces.
    nonisolated(unsafe) private static var hasFinishedLaunching = false

    /// Guards against running the work twice, and against the `didSet` above
    /// re-entering when the handler is cleared.
    nonisolated(unsafe) private static var hasRunDidFinishLaunching = false

    @MainActor
    private static func runDidFinishLaunching() {
        guard hasRunDidFinishLaunching == false, let work = onDidFinishLaunching else { return }
        hasRunDidFinishLaunching = true
        onDidFinishLaunching = nil
        work()
    }

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            Self.hasFinishedLaunching = true
            Self.runDidFinishLaunching()
        }
    }

    nonisolated func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls {
                Self.onOpenURL?(url)
            }
        }
    }

    nonisolated func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        MainActor.assumeIsolated {
            Self.onReopen?()
        }
        return true
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
