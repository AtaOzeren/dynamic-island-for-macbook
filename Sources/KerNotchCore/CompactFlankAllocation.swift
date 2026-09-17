import Foundation

/// How many standard icons the compact pill draws on each side of the notch.
///
/// Each side holds two. The trailing side belongs to the AI agents whenever any
/// are drawn, so the eye always finds them in one place; without agents
/// it takes the standard icons the leading side has no room for. The leading
/// side fills first and keeps the odd icon, so the most important icon is the
/// one the eye reaches first.
///
/// Whatever does not fit is not drawn at all. The expanded panel still lists it,
/// and an overflow counter would itself take one of the few places the pill has.
public struct CompactFlankAllocation: Equatable, Sendable {
    public static let slotsPerSide = 2

    public let leadingStandardCount: Int
    public let trailingStandardCount: Int

    public init(standardCount: Int, agentCount: Int) {
        let standardCount = max(standardCount, 0)
        if agentCount > 0 {
            leadingStandardCount = min(standardCount, Self.slotsPerSide)
            trailingStandardCount = 0
            return
        }

        let drawnCount = min(standardCount, Self.slotsPerSide * 2)
        leadingStandardCount = (drawnCount + 1) / 2
        trailingStandardCount = drawnCount - leadingStandardCount
    }
}
