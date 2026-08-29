import AppKit
import Foundation
import Testing
@testable import NotchFlowCore
@testable import NotchFlowProviders

@Suite("ScreenChangeObserver")
@MainActor
struct SystemScreenChangeObserverTests {
    private let builtIn = DisplayDescription(name: "Built-in Retina Display", isBuiltIn: true)
    private let studioDisplay = DisplayDescription(name: "Studio Display", isBuiltIn: false)

    private func makeObserver(
        applicationCenter: NotificationCenter,
        workspaceCenter: NotificationCenter,
        displays: @escaping @Sendable () -> [DisplayDescription] = { [] }
    ) -> SystemScreenChangeObserver {
        SystemScreenChangeObserver(
            applicationCenter: applicationCenter,
            workspaceCenter: workspaceCenter,
            currentDisplays: displays
        )
    }

    @Test("emits once per screen-parameters change with the current screen set")
    func emitsOnScreenParametersChange() {
        let applicationCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let displays = [builtIn, studioDisplay]
        let observer = makeObserver(
            applicationCenter: applicationCenter,
            workspaceCenter: workspaceCenter,
            displays: { displays }
        )

        var received: [ScreenChange] = []
        observer.startObserving { received.append($0) }
        applicationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(received == [ScreenChange(event: .screenParametersChanged, displays: displays)])
    }

    @Test("emits once per sleep and once per wake")
    func emitsOnSleepAndWake() {
        let applicationCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let observer = makeObserver(
            applicationCenter: applicationCenter,
            workspaceCenter: workspaceCenter,
            displays: { [self.builtIn] }
        )

        var received: [ScreenChangeEvent] = []
        observer.startObserving { received.append($0.event) }
        workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(received == [.systemWillSleep, .systemDidWake])
    }

    @Test("emits one event per notification, never coalescing repeats")
    func emitsOncePerNotification() {
        let applicationCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let observer = makeObserver(
            applicationCenter: applicationCenter,
            workspaceCenter: workspaceCenter
        )

        var received: [ScreenChangeEvent] = []
        observer.startObserving { received.append($0.event) }
        for _ in 0..<3 {
            applicationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        }

        #expect(received.count == 3)
    }

    @Test("stops emitting after stopObserving")
    func stopsEmittingAfterStop() {
        let applicationCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let observer = makeObserver(
            applicationCenter: applicationCenter,
            workspaceCenter: workspaceCenter
        )

        var received: [ScreenChangeEvent] = []
        observer.startObserving { received.append($0.event) }
        observer.stopObserving()
        applicationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        workspaceCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        #expect(received.isEmpty)
    }

    @Test("stopObserving is idempotent and safe before any start")
    func stopIsIdempotent() {
        let applicationCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let observer = makeObserver(
            applicationCenter: applicationCenter,
            workspaceCenter: workspaceCenter
        )

        observer.stopObserving()
        observer.startObserving { _ in }
        observer.stopObserving()
        observer.stopObserving()

        var received: [ScreenChangeEvent] = []
        observer.startObserving { received.append($0.event) }
        applicationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(received.count == 1)
    }

    @Test("restarting replaces the previous observer instead of stacking it")
    func restartReplacesObserver() {
        let applicationCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let observer = makeObserver(
            applicationCenter: applicationCenter,
            workspaceCenter: workspaceCenter
        )

        var stale: [ScreenChangeEvent] = []
        var fresh: [ScreenChangeEvent] = []
        observer.startObserving { stale.append($0.event) }
        observer.startObserving { fresh.append($0.event) }
        applicationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(stale.isEmpty)
        #expect(fresh.count == 1)
    }

    @Test("stops emitting once the observer is deallocated")
    func unsubscribesOnDeinit() {
        let applicationCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        var received: [ScreenChangeEvent] = []

        do {
            let observer = makeObserver(
                applicationCenter: applicationCenter,
                workspaceCenter: workspaceCenter
            )
            observer.startObserving { received.append($0.event) }
        }

        applicationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(received.isEmpty)
    }

    @Test("reads the screen set at emission time, not at subscription time")
    func readsScreenSetAtEmissionTime() {
        let applicationCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        nonisolated(unsafe) var connected = [builtIn, studioDisplay]
        let observer = makeObserver(
            applicationCenter: applicationCenter,
            workspaceCenter: workspaceCenter,
            displays: { connected }
        )

        var received: [[DisplayDescription]] = []
        observer.startObserving { received.append($0.displays) }
        connected = [builtIn]
        applicationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        #expect(received == [[builtIn]])
    }
}
