import AppKit
import KerNotchCore

/// What the integration needs to know about the Discord application itself.
@MainActor
public protocol DiscordWorkspaceObserving: AnyObject {
    var isDiscordInstalled: Bool { get }
    func startObservingLaunches(_ onLaunch: @escaping @MainActor () -> Void)
    func stopObservingLaunches()
}

/// The production workspace: installation through Launch Services, launches
/// through `NSWorkspace`'s own notification.
///
/// A launch notification is delivered once per application launch, so waiting
/// for Discord to start costs nothing while it is quit — no probing of its
/// socket path on a timer.
@MainActor
public final class NSWorkspaceDiscordObserver: DiscordWorkspaceObserving {
    private let workspace: NSWorkspace
    private var launchObserver: (any NSObjectProtocol)?

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    public var isDiscordInstalled: Bool {
        DiscordApplication.bundleIdentifiers.contains {
            workspace.urlForApplication(withBundleIdentifier: $0) != nil
        }
    }

    public func startObservingLaunches(_ onLaunch: @escaping @MainActor () -> Void) {
        stopObservingLaunches()
        launchObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let bundleIdentifier = application?.bundleIdentifier,
                DiscordApplication.owns(bundleIdentifier: bundleIdentifier)
            else { return }
            MainActor.assumeIsolated { onLaunch() }
        }
    }

    public func stopObservingLaunches() {
        guard let launchObserver else { return }
        workspace.notificationCenter.removeObserver(launchObserver)
        self.launchObserver = nil
    }
}
