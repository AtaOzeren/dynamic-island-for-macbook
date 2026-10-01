import Testing

@testable import KerNotch
@testable import KerNotchCore

/// Reading the window server's answer about each display's Spaces. The answer
/// itself comes from a private framework, so what is tested here is the one
/// part KerNotch owns: turning it into each display's current and full-screen
/// Spaces.
@Suite("ManagedDisplaySpaces")
struct ManagedDisplaySpacesTests {
    private static let builtInUUID = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
    private static let studioUUID = "C57A0833-2371-484E-93C4-1FB1F63EAF10"
    private static let fullScreen = ManagedDisplaySpaces.fullScreenSpaceType

    private static func space(_ id: Int, type: Int) -> [String: Any] {
        ["ManagedSpaceID": id, "type": type, "uuid": "space-\(id)"]
    }

    private static func display(_ identifier: String, current: [String: Any], spaces: [[String: Any]]) -> [String: Any] {
        ["Display Identifier": identifier, "Current Space": current, "Spaces": spaces]
    }

    @Test("a display showing a full-screen Space reports it, with every full-screen Space it has")
    func fullScreenDisplay() {
        let spaces = ManagedDisplaySpaces(managedDisplaySpaces: [
            Self.display(
                Self.studioUUID,
                current: Self.space(40, type: Self.fullScreen),
                spaces: [Self.space(3, type: 0), Self.space(40, type: Self.fullScreen), Self.space(41, type: Self.fullScreen)]
            )
        ])

        #expect(
            spaces.spaces(onDisplayWithUUID: Self.studioUUID)
                == DisplaySpaces(currentSpaceID: 40, isShowingFullScreen: true, fullScreenSpaceIDs: [40, 41])
        )
    }

    @Test("a display on a desktop reports the full-screen Spaces beside it")
    func desktopDisplay() {
        let spaces = ManagedDisplaySpaces(managedDisplaySpaces: [
            Self.display(
                Self.builtInUUID,
                current: Self.space(3, type: 0),
                spaces: [Self.space(3, type: 0), Self.space(40, type: Self.fullScreen)]
            )
        ])

        #expect(
            spaces.spaces(onDisplayWithUUID: Self.builtInUUID)
                == DisplaySpaces(currentSpaceID: 3, isShowingFullScreen: false, fullScreenSpaceIDs: [40])
        )
    }

    @Test("each display is read on its own")
    func displaysAreSeparate() {
        let spaces = ManagedDisplaySpaces(managedDisplaySpaces: [
            Self.display(Self.builtInUUID, current: Self.space(3, type: 0), spaces: [Self.space(3, type: 0)]),
            Self.display(
                Self.studioUUID,
                current: Self.space(40, type: Self.fullScreen),
                spaces: [Self.space(40, type: Self.fullScreen)]
            ),
        ])

        #expect(spaces.spaces(onDisplayWithUUID: Self.builtInUUID)?.isShowingFullScreen == false)
        #expect(spaces.spaces(onDisplayWithUUID: Self.studioUUID)?.isShowingFullScreen == true)
    }

    @Test("with one shared set of Spaces, every display reads the shared entry")
    func sharedSpacesCoverEveryDisplay() {
        let spaces = ManagedDisplaySpaces(managedDisplaySpaces: [
            Self.display(
                ManagedDisplaySpaces.allDisplaysIdentifier,
                current: Self.space(40, type: Self.fullScreen),
                spaces: [Self.space(40, type: Self.fullScreen)]
            )
        ])

        #expect(spaces.spaces(onDisplayWithUUID: Self.builtInUUID)?.isShowingFullScreen == true)
        #expect(spaces.spaces(onDisplayWithUUID: Self.studioUUID)?.isShowingFullScreen == true)
        #expect(spaces.spaces(onDisplayWithUUID: nil)?.isShowingFullScreen == true)
    }

    @Test("a display the window server does not list has no Spaces to read")
    func unlistedDisplay() {
        let spaces = ManagedDisplaySpaces(managedDisplaySpaces: [
            Self.display(Self.studioUUID, current: Self.space(3, type: 0), spaces: [Self.space(3, type: 0)])
        ])

        #expect(spaces.spaces(onDisplayWithUUID: Self.builtInUUID) == nil)
        #expect(spaces.spaces(onDisplayWithUUID: nil) == nil)
    }

    @Test("entries of an unexpected shape are skipped rather than trusted")
    func malformedEntriesAreSkipped() {
        let spaces = ManagedDisplaySpaces(managedDisplaySpaces: [
            ["Display Identifier": Self.studioUUID],
            ["Current Space": Self.space(40, type: Self.fullScreen)],
            ["Display Identifier": 7, "Current Space": Self.space(40, type: Self.fullScreen)],
            ["Display Identifier": Self.builtInUUID, "Current Space": ["type": Self.fullScreen]],
        ])

        #expect(spaces == .none)
    }

    @Test("Spaces of an unexpected shape are left out of the full-screen set")
    func malformedSpacesAreSkipped() {
        let spaces = ManagedDisplaySpaces(managedDisplaySpaces: [
            Self.display(
                Self.studioUUID,
                current: Self.space(3, type: 0),
                spaces: [["type": Self.fullScreen], ["ManagedSpaceID": 41, "type": "4"]]
            )
        ])

        #expect(spaces.spaces(onDisplayWithUUID: Self.studioUUID)?.fullScreenSpaceIDs == [])
    }

    @Test("no answer from the window server means no Spaces at all")
    func emptyAnswerIsNone() {
        #expect(ManagedDisplaySpaces(managedDisplaySpaces: []) == .none)
    }
}
