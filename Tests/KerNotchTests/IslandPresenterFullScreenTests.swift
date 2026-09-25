import AppKit
import Foundation
import Testing

@testable import KerNotch
@testable import KerNotchCore
@testable import KerNotchProviders
@testable import KerNotchUI

/// The General pane's full-screen switch, from the presenter's side: the
/// island on a display showing a full-screen app steps aside, and nothing
/// reads the window server's Spaces while the switch is off.
@Suite("IslandPresenter full screen", .serialized)
@MainActor
struct IslandPresenterFullScreenTests {
    private struct Harness {
        let presenter: IslandPresenter
        let fullScreenSpaces: FakeFullScreenSpaces
    }

    private static func makeHarness(hidesInFullScreen: Bool) -> Harness {
        let store = SettingsStore(storage: DictionarySettingsStorage())
        store[.hideInFullScreen] = hidesInFullScreen
        let fullScreenSpaces = FakeFullScreenSpaces()
        let presenter = IslandPresenter(
            manager: ActivityManager(),
            settingsStore: store,
            screenChanges: SilentScreenChanges(),
            fullScreenSpaces: fullScreenSpaces
        )
        return Harness(presenter: presenter, fullScreenSpaces: fullScreenSpaces)
    }

    /// Lets the island finish stepping aside, which it does on screen before
    /// the window is ordered out.
    private static func letTheIslandStepAside() {
        RunLoop.main.run(until: Date().addingTimeInterval(IslandMotion.default.withdrawalDuration + 0.1))
    }

    /// The display the island is on under the default display target.
    private static func islandDisplayIdentifier() throws -> String {
        try #require(
            selectDisplay(from: NSScreen.screens.map(DisplayDescription.init), preference: .automatic)
        ).identifier
    }

    @Test("an app in full screen on the island's display takes the island off screen")
    func fullScreenOnIslandDisplayHidesIsland() throws {
        let harness = Self.makeHarness(hidesInFullScreen: true)
        harness.presenter.start()

        harness.fullScreenSpaces.report([try Self.islandDisplayIdentifier()])
        Self.letTheIslandStepAside()

        #expect(harness.presenter.motionState.presentationState == .hidden)
    }

    @Test("leaving full screen brings the island back")
    func leavingFullScreenRestoresIsland() throws {
        let harness = Self.makeHarness(hidesInFullScreen: true)
        harness.presenter.start()
        harness.fullScreenSpaces.report([try Self.islandDisplayIdentifier()])

        harness.fullScreenSpaces.report([])

        #expect(harness.presenter.motionState.presentationState == .compact)
    }

    @Test("an app in full screen on another display leaves the island in place")
    func fullScreenElsewhereKeepsIsland() {
        let harness = Self.makeHarness(hidesInFullScreen: true)
        harness.presenter.start()

        harness.fullScreenSpaces.report(["another-display"])

        #expect(harness.presenter.motionState.presentationState == .compact)
    }

    @Test("launching into a full-screen app never orders the island in")
    func launchIntoFullScreenStaysHidden() throws {
        let harness = Self.makeHarness(hidesInFullScreen: true)
        harness.fullScreenSpaces.current = [try Self.islandDisplayIdentifier()]

        harness.presenter.start()

        #expect(harness.presenter.motionState.presentationState == .hidden)
    }

    @Test("with the switch off, the Spaces are never read and the island stays")
    func switchOffNeverObserves() {
        let harness = Self.makeHarness(hidesInFullScreen: false)

        harness.presenter.start()

        #expect(harness.fullScreenSpaces.isObserving == false)
        #expect(harness.presenter.motionState.presentationState == .compact)
    }

    @Test("switching on over a full-screen app takes the island away")
    func switchingOnHidesTheIsland() throws {
        let harness = Self.makeHarness(hidesInFullScreen: false)
        harness.presenter.start()
        harness.fullScreenSpaces.current = [try Self.islandDisplayIdentifier()]

        harness.presenter.applyFullScreenHiding(true)
        Self.letTheIslandStepAside()

        #expect(harness.fullScreenSpaces.isObserving)
        #expect(harness.presenter.motionState.presentationState == .hidden)
    }

    @Test("switching off brings a hidden island back and stops reading the Spaces")
    func switchingOffRestoresIsland() throws {
        let harness = Self.makeHarness(hidesInFullScreen: true)
        harness.presenter.start()
        harness.fullScreenSpaces.report([try Self.islandDisplayIdentifier()])

        harness.presenter.applyFullScreenHiding(false)

        #expect(harness.fullScreenSpaces.isObserving == false)
        #expect(harness.presenter.motionState.presentationState == .compact)
    }
}

@MainActor
private final class FakeFullScreenSpaces: FullScreenSpaceObserving {
    var current: Set<String> = []
    private var observer: FullScreenDisplaysObserver?

    var isObserving: Bool { observer != nil }

    func startObserving(_ observer: @escaping FullScreenDisplaysObserver) {
        self.observer = observer
        observer(current)
    }

    func stopObserving() {
        observer = nil
    }

    func report(_ displays: Set<String>) {
        current = displays
        observer?(displays)
    }
}

@MainActor
private final class SilentScreenChanges: ScreenChangeObserving {
    func startObserving(_: @escaping ScreenChangeObserver) {}
    func stopObserving() {}
}
