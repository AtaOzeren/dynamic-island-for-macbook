import AppKit
import Foundation
import NotchFlowCore

/// Wraps the system notifications that invalidate display selection — screen
/// parameter changes plus sleep and wake — and emits the screen set as it is at
/// the moment each notification arrives. Never polls.
@MainActor
public final class SystemScreenChangeObserver: ScreenChangeObserving {
    private let applicationCenter: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private let currentDisplays: @Sendable () -> [DisplayDescription]
    private let subscriptions = NotificationSubscriptionBag()

    public convenience init() {
        self.init(
            applicationCenter: .default,
            workspaceCenter: NSWorkspace.shared.notificationCenter,
            currentDisplays: {
                MainActor.assumeIsolated { NSScreen.screens.map(DisplayDescription.init) }
            }
        )
    }

    init(
        applicationCenter: NotificationCenter,
        workspaceCenter: NotificationCenter,
        currentDisplays: @escaping @Sendable () -> [DisplayDescription]
    ) {
        self.applicationCenter = applicationCenter
        self.workspaceCenter = workspaceCenter
        self.currentDisplays = currentDisplays
    }

    public func startObserving(_ observer: @escaping ScreenChangeObserver) {
        stopObserving()

        subscribe(
            to: NSApplication.didChangeScreenParametersNotification,
            on: applicationCenter,
            emitting: .screenParametersChanged,
            to: observer
        )
        subscribe(
            to: NSWorkspace.willSleepNotification,
            on: workspaceCenter,
            emitting: .systemWillSleep,
            to: observer
        )
        subscribe(
            to: NSWorkspace.didWakeNotification,
            on: workspaceCenter,
            emitting: .systemDidWake,
            to: observer
        )
    }

    public func stopObserving() {
        subscriptions.removeAll()
    }

    private func subscribe(
        to name: Notification.Name,
        on center: NotificationCenter,
        emitting event: ScreenChangeEvent,
        to observer: @escaping ScreenChangeObserver
    ) {
        let displays = currentDisplays
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                observer(ScreenChange(event: event, displays: displays()))
            }
        }

        subscriptions.add(token, to: center)
    }
}

/// Owns the notification tokens so they are released both on `stopObserving` and
/// when the observer itself is deallocated, without a main-actor-isolated `deinit`.
private final class NotificationSubscriptionBag: @unchecked Sendable {
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

    deinit {
        removeAll()
    }
}

extension DisplayDescription {
    init(_ screen: NSScreen) {
        self.init(name: screen.localizedName, isBuiltIn: screen.safeAreaInsets.top > 0)
    }
}
