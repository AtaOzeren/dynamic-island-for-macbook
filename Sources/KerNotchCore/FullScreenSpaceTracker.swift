/// One display's Spaces, as the window server lists them.
public struct DisplaySpaces: Equatable, Sendable {
    public let currentSpaceID: Int
    public let isShowingFullScreen: Bool
    /// Every full-screen Space on the display, the current one included.
    public let fullScreenSpaceIDs: Set<Int>

    public init(currentSpaceID: Int, isShowingFullScreen: Bool, fullScreenSpaceIDs: Set<Int>) {
        self.currentSpaceID = currentSpaceID
        self.isShowingFullScreen = isShowingFullScreen
        self.fullScreenSpaceIDs = fullScreenSpaceIDs
    }
}

/// Decides which displays the island steps aside on: those showing a
/// full-screen app, and those an app is going full screen on right now.
///
/// The second group is what keeps the island from flashing over a video that
/// goes full screen. The window server lists the new full-screen Space about
/// half a second before it announces the switch, and for that half second the
/// Space slides in with the island drawn over it. A full-screen Space that was
/// not there at the previous reading is where an app is heading, so its
/// display counts as full screen until the display's current Space changes;
/// from then on the current Space answers alone.
public struct FullScreenSpaceTracker: Equatable, Sendable {
    private var knownFullScreenSpaceIDs: [String: Set<Int>] = [:]
    private var currentSpaceIDs: [String: Int] = [:]
    private var arrivingSpaceIDs: [String: Set<Int>] = [:]

    public init() {}

    /// Takes in a reading keyed by display and returns the displays in full
    /// screen or entering it. A display's first reading only sets what is
    /// already there, so full-screen apps left on other Spaces never count as
    /// arriving.
    public mutating func displaysInFullScreen(after reading: [String: DisplaySpaces]) -> Set<String> {
        var displays: Set<String> = []
        for (identifier, spaces) in reading {
            let arriving = arrivingSpaces(on: identifier, in: spaces)
            arrivingSpaceIDs[identifier] = arriving
            knownFullScreenSpaceIDs[identifier] = spaces.fullScreenSpaceIDs
            currentSpaceIDs[identifier] = spaces.currentSpaceID
            if spaces.isShowingFullScreen || arriving.isEmpty == false {
                displays.insert(identifier)
            }
        }
        forgetDisplays(missingFrom: reading)
        return displays
    }

    /// The full-screen Spaces created on this display since the last reading
    /// that it has not switched to yet. Any switch settles them: the current
    /// Space is the answer after one, and a Space that vanished was abandoned.
    private func arrivingSpaces(on identifier: String, in spaces: DisplaySpaces) -> Set<Int> {
        guard
            let known = knownFullScreenSpaceIDs[identifier],
            currentSpaceIDs[identifier] == spaces.currentSpaceID
        else {
            return []
        }
        let created = spaces.fullScreenSpaceIDs.subtracting(known)
        return arrivingSpaceIDs[identifier, default: []]
            .union(created)
            .intersection(spaces.fullScreenSpaceIDs)
    }

    private mutating func forgetDisplays(missingFrom reading: [String: DisplaySpaces]) {
        for identifier in Set(knownFullScreenSpaceIDs.keys).subtracting(reading.keys) {
            knownFullScreenSpaceIDs[identifier] = nil
            currentSpaceIDs[identifier] = nil
            arrivingSpaceIDs[identifier] = nil
        }
    }
}
