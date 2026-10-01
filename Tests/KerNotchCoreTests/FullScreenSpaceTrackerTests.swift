import Testing

@testable import KerNotchCore

@Suite("FullScreenSpaceTracker")
struct FullScreenSpaceTrackerTests {
    private static let display = "1"
    private static let otherDisplay = "2"
    private static let desktop = 3
    private static let otherDesktop = 5

    private static func onDesktop(_ current: Int = desktop, fullScreenSpaces: Set<Int> = []) -> DisplaySpaces {
        DisplaySpaces(currentSpaceID: current, isShowingFullScreen: false, fullScreenSpaceIDs: fullScreenSpaces)
    }

    private static func inFullScreen(_ current: Int, fullScreenSpaces: Set<Int>? = nil) -> DisplaySpaces {
        DisplaySpaces(
            currentSpaceID: current,
            isShowingFullScreen: true,
            fullScreenSpaceIDs: fullScreenSpaces ?? [current]
        )
    }

    @Test("a display on a desktop is not in full screen")
    func desktopIsNotFullScreen() {
        var tracker = FullScreenSpaceTracker()

        #expect(tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop()]).isEmpty)
    }

    @Test("a display showing a full-screen Space is in full screen")
    func showingFullScreenCounts() {
        var tracker = FullScreenSpaceTracker()

        #expect(tracker.displaysInFullScreen(after: [Self.display: Self.inFullScreen(40)]) == [Self.display])
    }

    @Test("a full-screen Space created on a display counts before the switch to it is announced")
    func arrivingFullScreenCountsEarly() {
        var tracker = FullScreenSpaceTracker()
        _ = tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop()])

        let entering = tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop(fullScreenSpaces: [40])])

        #expect(entering == [Self.display])
    }

    @Test("the arriving Space keeps counting until the display switches")
    func arrivingSpaceHoldsUntilSwitch() {
        var tracker = FullScreenSpaceTracker()
        _ = tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop()])
        _ = tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop(fullScreenSpaces: [40])])

        let stillEntering = tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop(fullScreenSpaces: [40])])
        let switched = tracker.displaysInFullScreen(after: [Self.display: Self.inFullScreen(40)])

        #expect(stillEntering == [Self.display])
        #expect(switched == [Self.display])
    }

    @Test("full-screen apps already on other Spaces at the first reading never count as arriving")
    func existingFullScreenSpacesAreBaseline() {
        var tracker = FullScreenSpaceTracker()

        let first = tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop(fullScreenSpaces: [40, 41])])
        let second = tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop(fullScreenSpaces: [40, 41])])

        #expect(first.isEmpty)
        #expect(second.isEmpty)
    }

    @Test("leaving full screen for a desktop brings the display back")
    func leavingFullScreenSettles() {
        var tracker = FullScreenSpaceTracker()
        _ = tracker.displaysInFullScreen(after: [Self.display: Self.inFullScreen(40)])

        #expect(tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop()]).isEmpty)
    }

    @Test("switching away before reaching the new Space settles on the desktop")
    func switchingAwaySettles() {
        var tracker = FullScreenSpaceTracker()
        _ = tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop()])
        _ = tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop(fullScreenSpaces: [40])])

        let settled = tracker.displaysInFullScreen(
            after: [Self.display: Self.onDesktop(Self.otherDesktop, fullScreenSpaces: [40])]
        )

        #expect(settled.isEmpty)
    }

    @Test("a full-screen Space that vanishes before the switch is abandoned")
    func vanishedSpaceIsAbandoned() {
        var tracker = FullScreenSpaceTracker()
        _ = tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop()])
        _ = tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop(fullScreenSpaces: [40])])

        #expect(tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop()]).isEmpty)
    }

    @Test("switching desktops beside a full-screen app leaves the display out")
    func desktopSwitchBesideFullScreenApp() {
        var tracker = FullScreenSpaceTracker()
        _ = tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop(fullScreenSpaces: [40])])

        let switched = tracker.displaysInFullScreen(
            after: [Self.display: Self.onDesktop(Self.otherDesktop, fullScreenSpaces: [40])]
        )

        #expect(switched.isEmpty)
    }

    @Test("an app going full screen on one display leaves the other display out")
    func eachDisplayAnswersForItself() {
        var tracker = FullScreenSpaceTracker()
        _ = tracker.displaysInFullScreen(after: [
            Self.display: Self.onDesktop(),
            Self.otherDisplay: Self.onDesktop(Self.otherDesktop),
        ])

        let entering = tracker.displaysInFullScreen(after: [
            Self.display: Self.onDesktop(),
            Self.otherDisplay: Self.onDesktop(Self.otherDesktop, fullScreenSpaces: [40]),
        ])

        #expect(entering == [Self.otherDisplay])
    }

    @Test("a display that comes back after being unplugged starts from a fresh baseline")
    func reattachedDisplayStartsFresh() {
        var tracker = FullScreenSpaceTracker()
        _ = tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop()])
        _ = tracker.displaysInFullScreen(after: [:])

        let reattached = tracker.displaysInFullScreen(after: [Self.display: Self.onDesktop(fullScreenSpaces: [40])])

        #expect(reattached.isEmpty)
    }

    @Test("no reading means no display is in full screen")
    func emptyReading() {
        var tracker = FullScreenSpaceTracker()

        #expect(tracker.displaysInFullScreen(after: [:]).isEmpty)
    }
}
