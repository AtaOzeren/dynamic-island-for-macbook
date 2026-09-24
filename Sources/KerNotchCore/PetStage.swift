import CoreGraphics

/// How much of the compact pill's leading flank the pet has to itself.
///
/// The pet lives in the places the activities' icons leave free on the leading
/// flank. The icons keep every rule they had — the pet never takes a place one
/// of them needs — so the pet roams while the flank is empty, sits at its outer
/// edge beside a single icon, and leaves the island when the flank is full.
public enum PetStage: Equatable, Sendable {
    /// Both places free: the pet walks the whole flank.
    case roaming
    /// One place free: the pet sits in the outer one.
    case resting
    /// No place free: the pet is off the island.
    case away

    public init(freePlaceCount: Int) {
        switch freePlaceCount {
        case ..<1: self = .away
        case 1: self = .resting
        default: self = .roaming
        }
    }
}

/// Where on the leading flank the pet can stand, in whole points from the
/// flank's outer edge.
///
/// Whole points because the art is drawn one point per pixel: a pet standing
/// between two points would have every pixel straddle a device-pixel boundary
/// and shimmer as it walked.
public struct PetStageGeometry: Equatable, Sendable {
    public let spriteWidth: Int
    /// One icon place on the pill.
    public let placeWidth: Int
    /// The whole leading flank: every place and the gaps between them.
    public let flankWidth: Int
    /// The pill's own margin, outside the flank.
    public let edgeInset: Int

    public init(pill: CompactPillMetrics, spriteWidth: Int) {
        self.spriteWidth = spriteWidth
        placeWidth = Int(pill.slotWidth.rounded())
        flankWidth = Int(
            compactSideWidth(slotCount: CompactFlankAllocation.slotsPerSide, metrics: pill).rounded()
        )
        edgeInset = Int(pill.edgeInset.rounded())
    }

    /// Every position that keeps the pet wholly on the flank.
    public var roamingRange: ClosedRange<Int> {
        0...max(flankWidth - spriteWidth, 0)
    }

    /// Where the pet sits beside a single icon: centred in the outer place,
    /// which the icons leave free because they fill the flank from the notch.
    public var restingPosition: Int {
        max((placeWidth - spriteWidth) / 2, 0)
    }

    /// Just past the pill's outer edge, where nothing of the pet is drawn.
    public var offstagePosition: Int {
        -(edgeInset + spriteWidth)
    }
}
