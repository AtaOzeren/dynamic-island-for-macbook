import AppKit
import Foundation
import Testing

@testable import KerNotchCore
@testable import KerNotchProviders

@Suite("FullScreenSpaceObserver")
@MainActor
struct SystemFullScreenSpaceObserverTests {
    private static let display = "1"
    private static let desktop = DisplaySpaces(currentSpaceID: 3, isShowingFullScreen: false, fullScreenSpaceIDs: [])
    private static let enteringFullScreen = DisplaySpaces(
        currentSpaceID: 3,
        isShowingFullScreen: false,
        fullScreenSpaceIDs: [40]
    )
    private static let fullScreen = DisplaySpaces(currentSpaceID: 40, isShowingFullScreen: true, fullScreenSpaceIDs: [40])

    @MainActor
    private struct Harness {
        let applicationCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let spaces = DisplaySpacesSource()
        let observer: SystemFullScreenSpaceObserver

        init() {
            observer = SystemFullScreenSpaceObserver(
                applicationCenter: applicationCenter,
                workspaceCenter: workspaceCenter,
                currentSpaces: spaces.current
            )
        }

        func finishSpaceSwitch() {
            workspaceCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        }

        func startSpaceSwitch() {
            applicationCenter.post(name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        }

        func changeScreens() {
            applicationCenter.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        }
    }

    @Test("reports the displays already in full screen as soon as it starts")
    func reportsAtStart() {
        let harness = Harness()
        harness.spaces.reading = [Self.display: Self.fullScreen]

        var received: [Set<String>] = []
        harness.observer.startObserving { received.append($0) }

        #expect(received == [[Self.display]])
    }

    @Test("re-reads the Spaces when a Space switch ends")
    func reportsOnSpaceSwitch() {
        let harness = Harness()
        harness.spaces.reading = [Self.display: Self.desktop]
        var received: [Set<String>] = []
        harness.observer.startObserving { received.append($0) }

        harness.spaces.reading = [Self.display: Self.fullScreen]
        harness.finishSpaceSwitch()
        harness.spaces.reading = [Self.display: Self.desktop]
        harness.finishSpaceSwitch()

        #expect(received == [[], [Self.display], []])
    }

    @Test("reports an app going full screen as soon as the switch to its Space starts")
    func reportsWhenSwitchStarts() {
        let harness = Harness()
        harness.spaces.reading = [Self.display: Self.desktop]
        var received: [Set<String>] = []
        harness.observer.startObserving { received.append($0) }

        harness.spaces.reading = [Self.display: Self.enteringFullScreen]
        harness.startSpaceSwitch()

        #expect(received == [[], [Self.display]])
    }

    @Test("re-reads the Spaces when a display comes or goes")
    func reportsOnScreenChange() {
        let harness = Harness()
        var received: [Set<String>] = []
        harness.observer.startObserving { received.append($0) }

        harness.spaces.reading = ["2": Self.fullScreen]
        harness.changeScreens()

        #expect(received == [[], ["2"]])
    }

    @Test("stops reporting after stopObserving")
    func stopsReporting() {
        let harness = Harness()
        var received: [Set<String>] = []
        harness.observer.startObserving { received.append($0) }

        harness.observer.stopObserving()
        harness.finishSpaceSwitch()
        harness.startSpaceSwitch()
        harness.changeScreens()

        #expect(received == [[]])
    }

    @Test("restarting replaces the previous observer instead of stacking it")
    func restartReplacesObserver() {
        let harness = Harness()
        var stale: [Set<String>] = []
        var fresh: [Set<String>] = []
        harness.observer.startObserving { stale.append($0) }

        harness.observer.startObserving { fresh.append($0) }
        harness.finishSpaceSwitch()

        #expect(stale == [[]])
        #expect(fresh == [[], []])
    }

    /// Switched off and on again later, the full-screen apps opened meanwhile
    /// are simply there: counting them as arriving would hide the island on a
    /// desktop the user never left.
    @Test("restarting takes full-screen Spaces created meanwhile as already there")
    func restartStartsFromFreshReading() {
        let harness = Harness()
        harness.spaces.reading = [Self.display: Self.desktop]
        harness.observer.startObserving { _ in }
        harness.observer.stopObserving()
        harness.spaces.reading = [Self.display: Self.enteringFullScreen]

        var received: [Set<String>] = []
        harness.observer.startObserving { received.append($0) }
        harness.startSpaceSwitch()

        #expect(received == [[], []])
    }

    @Test("stops reporting once the observer is deallocated")
    func unsubscribesOnDeinit() {
        let workspaceCenter = NotificationCenter()
        var received: [Set<String>] = []

        do {
            let observer = SystemFullScreenSpaceObserver(
                applicationCenter: NotificationCenter(),
                workspaceCenter: workspaceCenter,
                currentSpaces: { [:] }
            )
            observer.startObserving { received.append($0) }
        }

        workspaceCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        #expect(received == [[]])
    }
}

@MainActor
private final class DisplaySpacesSource {
    var reading: [String: DisplaySpaces] = [:]

    func current() -> [String: DisplaySpaces] {
        reading
    }
}
