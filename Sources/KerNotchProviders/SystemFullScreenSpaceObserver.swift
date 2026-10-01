import AppKit
import Foundation
import KerNotchCore

/// Follows which displays are showing an app in full screen, or switching to
/// one, re-reading the window server's Space records when a Space switch
/// starts, when it ends, and when the screen set changes. Never polls.
///
/// A switch announces its end through `NSWorkspace`, half a second after the
/// new Space started sliding in. Its start has no notification of its own,
/// but it covers every window KerNotch has on that display, so a change in
/// one of their occlusion states is the moment to look for a full-screen Space
/// that has just been created.
///
/// The records themselves are read through the closure the composition root
/// hands in: only a private framework has them, and private frameworks stay
/// in the app target (`docs/06-activity-providers.md`).
@MainActor
public final class SystemFullScreenSpaceObserver: FullScreenSpaceObserving {
    private let applicationCenter: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private let currentSpaces: @MainActor () -> [String: DisplaySpaces]
    private let subscriptions = NotificationSubscriptionBag()
    private var tracker = FullScreenSpaceTracker()

    public convenience init(currentSpaces: @escaping @MainActor () -> [String: DisplaySpaces]) {
        self.init(
            applicationCenter: .default,
            workspaceCenter: NSWorkspace.shared.notificationCenter,
            currentSpaces: currentSpaces
        )
    }

    init(
        applicationCenter: NotificationCenter,
        workspaceCenter: NotificationCenter,
        currentSpaces: @escaping @MainActor () -> [String: DisplaySpaces]
    ) {
        self.applicationCenter = applicationCenter
        self.workspaceCenter = workspaceCenter
        self.currentSpaces = currentSpaces
    }

    /// Starts from a fresh reading, so full-screen Spaces created while
    /// nothing was observing are taken as already there rather than arriving.
    public func startObserving(_ observer: @escaping FullScreenDisplaysObserver) {
        stopObserving()
        tracker = FullScreenSpaceTracker()

        subscribe(to: NSWindow.didChangeOcclusionStateNotification, on: applicationCenter, observer)
        subscribe(to: NSWorkspace.activeSpaceDidChangeNotification, on: workspaceCenter, observer)
        subscribe(to: NSApplication.didChangeScreenParametersNotification, on: applicationCenter, observer)
        report(to: observer)
    }

    public func stopObserving() {
        subscriptions.removeAll()
    }

    private func subscribe(
        to name: Notification.Name,
        on center: NotificationCenter,
        _ observer: @escaping FullScreenDisplaysObserver
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.report(to: observer)
            }
        }

        subscriptions.add(token, to: center)
    }

    private func report(to observer: FullScreenDisplaysObserver) {
        observer(tracker.displaysInFullScreen(after: currentSpaces()))
    }
}
