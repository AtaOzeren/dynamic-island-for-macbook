import AppKit
import Foundation
import KerNotchCore
import KerNotchProviders

/// Which Spaces each display has and which one it is showing, as the window
/// server reports them.
///
/// A full-screen app lives in a Space of its own, and the Space's type is the
/// only record that says so: the island's panel joins every Space, full-screen
/// ones included, so AppKit never tells it that one is up, and a window that
/// merely fills the screen looks the same as a full-screen one by its bounds.
struct ManagedDisplaySpaces: Equatable {
    /// What the window server calls the one shared entry while "Displays have
    /// separate Spaces" is off; its Spaces are every display's.
    static let allDisplaysIdentifier = "Main"
    static let fullScreenSpaceType = 4

    static let none = ManagedDisplaySpaces(displaysByUUID: [:])

    let displaysByUUID: [String: DisplaySpaces]

    init(displaysByUUID: [String: DisplaySpaces]) {
        self.displaysByUUID = displaysByUUID
    }

    /// Reads the answer `SLSCopyManagedDisplaySpaces` gives: one entry per
    /// display, naming the display, its current Space and every Space it has.
    /// Entries of any other shape are skipped rather than trusted.
    init(managedDisplaySpaces: [[String: Any]]) {
        var displaysByUUID: [String: DisplaySpaces] = [:]
        for display in managedDisplaySpaces {
            guard
                let identifier = display["Display Identifier"] as? String,
                let currentSpace = display["Current Space"] as? [String: Any],
                let currentSpaceID = currentSpace["ManagedSpaceID"] as? Int
            else {
                continue
            }
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            displaysByUUID[identifier] = DisplaySpaces(
                currentSpaceID: currentSpaceID,
                isShowingFullScreen: Self.isFullScreen(currentSpace),
                fullScreenSpaceIDs: Set(
                    spaces.filter(Self.isFullScreen).compactMap { $0["ManagedSpaceID"] as? Int }
                )
            )
        }
        self.init(displaysByUUID: displaysByUUID)
    }

    /// A display's Spaces, or the shared ones while displays do not have
    /// Spaces of their own.
    func spaces(onDisplayWithUUID uuid: String?) -> DisplaySpaces? {
        uuid.flatMap { displaysByUUID[$0] } ?? displaysByUUID[Self.allDisplaysIdentifier]
    }

    private static func isFullScreen(_ space: [String: Any]) -> Bool {
        (space["type"] as? Int) == fullScreenSpaceType
    }
}

/// The window server's private Space records, reached through SkyLight.
///
/// Resolved at runtime, the way the MediaRemote bridge is, so a macOS that no
/// longer exports these symbols leaves the island visible over full-screen
/// apps instead of failing to launch.
enum WindowServerSpaces {
    private typealias MainConnectionFunction = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFunction = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private struct Functions {
        let mainConnection: MainConnectionFunction
        let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFunction
    }

    private static let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    private static let functions: Functions? = {
        guard
            let handle = dlopen(skyLightPath, RTLD_LAZY),
            let mainConnection = dlsym(handle, "SLSMainConnectionID"),
            let copyManagedDisplaySpaces = dlsym(handle, "SLSCopyManagedDisplaySpaces")
        else {
            return nil
        }
        return Functions(
            mainConnection: unsafeBitCast(mainConnection, to: MainConnectionFunction.self),
            copyManagedDisplaySpaces: unsafeBitCast(
                copyManagedDisplaySpaces,
                to: CopyManagedDisplaySpacesFunction.self
            )
        )
    }()

    /// The Spaces of every attached display, keyed by
    /// `DisplayDescription.identifier`.
    @MainActor
    static func currentSpaces() -> [String: DisplaySpaces] {
        let managedSpaces = current()
        var spacesByDisplay: [String: DisplaySpaces] = [:]
        for screen in NSScreen.screens {
            spacesByDisplay[DisplayDescription(screen).identifier] = managedSpaces.spaces(
                onDisplayWithUUID: screen.displayUUID
            )
        }
        return spacesByDisplay
    }

    private static func current() -> ManagedDisplaySpaces {
        guard
            let functions,
            let spaces = functions.copyManagedDisplaySpaces(functions.mainConnection())?.takeRetainedValue(),
            let displays = spaces as? [[String: Any]]
        else {
            return .none
        }
        return ManagedDisplaySpaces(managedDisplaySpaces: displays)
    }
}

extension NSScreen {
    /// The display's UUID, the name the window server's Space records use.
    fileprivate var displayUUID: String? {
        guard
            let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            let uuid = CGDisplayCreateUUIDFromDisplayID(screenNumber.uint32Value)?.takeRetainedValue()
        else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
