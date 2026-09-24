import Foundation

/// How strongly an activity claims a place in the compact pill when there is not
/// room for everything, most important first.
///
/// Separate from `ActivityPriority` and `ActivityOrderBand`, which order the
/// expanded list. The list can show everything, so it orders for reading: what
/// is playing sits at the top because it is the card the user glances at. The
/// pill has four places at most, so it orders for keeping: a track is the first
/// icon to give its place up to a call or a capture the user must not miss.
public enum CompactRank: Int, CaseIterable, Comparable, Sendable {
    /// The screen or the microphone is being captured.
    case capture
    /// A voice call holds the microphone.
    case call
    /// The island explaining something the user did not witness.
    case notice
    /// Something has finished and is waiting for the user.
    case alert
    /// A short-lived transition, such as the charger going in or coming out.
    case transition
    /// Work the user started and is keeping an eye on.
    case tracking
    /// Media playing in the background.
    case ambient

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
