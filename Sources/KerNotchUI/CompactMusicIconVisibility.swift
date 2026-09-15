import Foundation

/// When the compact pill shows the music icon.
///
/// While a track plays, always: the moving bars are the playback status, and a
/// status that vanishes after a few seconds says nothing about the next hour.
/// Once it pauses, the still note stays long enough to notice the pause and to
/// reach for play, then gives its width back to the pill — a paused player can
/// sit untouched for hours, and the notch is not the place to park it.
///
/// Held by the presenter's clocks rather than by the compact view: that view is
/// rebuilt every time the island expands and collapses, so a countdown kept in
/// view state started over on every hover.
public struct CompactMusicIconVisibility: Equatable, Sendable {
    public static let pausedVisibleDuration: TimeInterval = 20

    /// When each paused music slot was first seen paused.
    private var pauseStarts: [String: Date] = [:]

    public init() {}

    /// Records which music slots are paused as of `now`.
    ///
    /// A slot that keeps reporting paused keeps its first instant, so new
    /// artwork or a track skipped while paused does not restart the countdown.
    /// A slot that plays or disappears forgets it, so the next pause counts
    /// from zero.
    public mutating func advance(slots: [CompactSlot], now: Date) {
        let pausedSlotIDs = Set(slots.filter(\.isPausedMusic).map(\.id))
        pauseStarts = pauseStarts.filter { pausedSlotIDs.contains($0.key) }
        for slotID in pausedSlotIDs where pauseStarts[slotID] == nil {
            pauseStarts[slotID] = now
        }
    }

    /// The paused slots whose time on screen is up.
    public func hiddenSlotIDs(at now: Date) -> Set<String> {
        Set(pauseStarts.filter { now >= Self.hideTime(forPauseAt: $0.value) }.keys)
    }

    /// The next moment a paused slot leaves, or `nil` when none is counting down.
    public func nextDeadline(after now: Date) -> Date? {
        pauseStarts.values
            .map(Self.hideTime(forPauseAt:))
            .filter { $0 > now }
            .min()
    }

    private static func hideTime(forPauseAt pauseStart: Date) -> Date {
        pauseStart.addingTimeInterval(pausedVisibleDuration)
    }
}

extension CompactSlot {
    /// A music slot whose track is not advancing.
    var isPausedMusic: Bool {
        musicSourceIdentity != nil && isPlayingMusic == false
    }
}
