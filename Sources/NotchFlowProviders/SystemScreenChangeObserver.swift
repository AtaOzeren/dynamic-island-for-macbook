import AppKit
import Foundation
import NotchFlowCore

/// Wraps the system notifications that invalidate display selection — screen
/// parameter changes plus sleep and wake — and emits the screen set as it is at
/// the moment each event is delivered. Never polls.
@MainActor
public final class SystemScreenChangeObserver: ScreenChangeObserving {
    private let applicationCenter: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private let currentDisplays: @Sendable () -> [DisplayDescription]
    private let debounceInterval: Duration
    private let subscriptions = NotificationSubscriptionBag()
    private var pendingScreenChange: Task<Void, Never>?

    public convenience init(debounceInterval: Duration = .milliseconds(300)) {
        self.init(
            applicationCenter: .default,
            workspaceCenter: NSWorkspace.shared.notificationCenter,
            debounceInterval: debounceInterval,
            currentDisplays: {
                MainActor.assumeIsolated { NSScreen.screens.map(DisplayDescription.init) }
            }
        )
    }

    init(
        applicationCenter: NotificationCenter,
        workspaceCenter: NotificationCenter,
        debounceInterval: Duration = .milliseconds(300),
        currentDisplays: @escaping @Sendable () -> [DisplayDescription]
    ) {
        self.applicationCenter = applicationCenter
        self.workspaceCenter = workspaceCenter
        self.debounceInterval = debounceInterval
        self.currentDisplays = currentDisplays
    }

    public func startObserving(_ observer: @escaping ScreenChangeObserver) {
        stopObserving()

        subscribe(
            to: NSApplication.didChangeScreenParametersNotification,
            on: applicationCenter
        ) { [weak self] in
            self?.scheduleScreenParametersChanged(to: observer)
        }
        subscribe(
            to: NSWorkspace.willSleepNotification,
            on: workspaceCenter
        ) { [weak self] in
            self?.emit(.systemWillSleep, to: observer)
        }
        subscribe(
            to: NSWorkspace.didWakeNotification,
            on: workspaceCenter
        ) { [weak self] in
            self?.emit(.systemDidWake, to: observer)
        }
    }

    public func stopObserving() {
        pendingScreenChange?.cancel()
        pendingScreenChange = nil
        subscriptions.removeAll()
    }

    private func subscribe(
        to name: Notification.Name,
        on center: NotificationCenter,
        action: @escaping @MainActor () -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }

        subscriptions.add(token, to: center)
    }

    private func scheduleScreenParametersChanged(to observer: @escaping ScreenChangeObserver) {
        pendingScreenChange?.cancel()
        let interval = debounceInterval
        guard interval > .zero else {
            emit(.screenParametersChanged, to: observer)
            return
        }
        pendingScreenChange = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            pendingScreenChange = nil
            emit(.screenParametersChanged, to: observer)
        }
    }

    private func emit(_ event: ScreenChangeEvent, to observer: ScreenChangeObserver) {
        observer(ScreenChange(event: event, displays: currentDisplays()))
    }

    deinit {
        pendingScreenChange?.cancel()
    }
}

/// Owns the notification tokens so they are released both on `stopObserving` and
/// when the owner itself is deallocated, without a main-actor-isolated `deinit`.
///
/// Shared by every notification-backed observer in this module: unsubscribing is
/// the one piece of their lifecycle that is easy to get subtly wrong, so it has
/// exactly one implementation.
@MainActor
final class NotificationSubscriptionBag {
    private var tokens: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    func add(_ token: any NSObjectProtocol, to center: NotificationCenter) {
        tokens.append((center, token))
    }

    func removeAll() {
        for subscription in tokens {
            subscription.center.removeObserver(subscription.token)
        }

        tokens.removeAll()
    }

    isolated deinit {
        removeAll()
    }
}

extension DisplayDescription {
    public init(_ screen: NSScreen) {
        self.init(
            identifier: screen.notchFlowIdentifier,
            name: screen.localizedName,
            isBuiltIn: screen.isBuiltIn
        )
    }
}

extension ScreenDescription {
    /// Translates a live `NSScreen` into the geometry shape the core reasons
    /// about, so `NotchFlowCore` and `NotchFlowUI` never touch `NSScreen`.
    public init(_ screen: NSScreen) {
        self.init(
            frame: screen.frame,
            safeAreaInsets: ScreenSafeAreaInsets(top: screen.safeAreaInsets.top),
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
            isBuiltIn: screen.isBuiltIn
        )
    }
}

extension NSScreen {
    fileprivate var notchFlowIdentifier: String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.stringValue
            ?? "\(localizedName):\(frame.origin.x):\(frame.origin.y)"
    }

    /// A screen is built in when the window server says its display is; the
    /// safe-area inset is the fallback for the rare screen that reports no
    /// display number.
    fileprivate var isBuiltIn: Bool {
        let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let displayID = screenNumber?.uint32Value else {
            return safeAreaInsets.top > 0
        }
        return CGDisplayIsBuiltin(displayID) != 0
    }
}
