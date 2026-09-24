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

/// Where on the island the pet can stand, in whole points from its outer edge.
///
/// On the compact pill that is the leading flank; on the open island it is the
/// strip beside the notch, above the cards, which is wider. Whole points
/// because every frame and every step of the pet's routine lands on one: at
/// two image pixels to a point, a point is a whole device pixel on a Retina
/// panel, and the art never straddles one.
public struct PetStageGeometry: Equatable, Sendable {
    public let spriteWidth: Int
    /// One icon place on the pill.
    public let placeWidth: Int
    /// Where the pet can be: every place of the flank and the gaps between
    /// them, or the open island's strip.
    public let flankWidth: Int
    /// The island's own margin, outside the flank.
    public let edgeInset: Int
    /// The gap between the flank and the notch, where nothing stands but a
    /// reaction's effects still show.
    public let notchGap: Int

    public init(pill: CompactPillMetrics, spriteWidth: Int) {
        self.init(
            spriteWidth: spriteWidth,
            placeWidth: Int(pill.slotWidth.rounded()),
            flankWidth: Int(
                compactSideWidth(slotCount: CompactFlankAllocation.slotsPerSide, metrics: pill).rounded()
            ),
            edgeInset: Int(pill.edgeInset.rounded()),
            notchGap: Int(pill.slotSpacing.rounded())
        )
    }

    /// The open island's strip, `stripWidth` points from its outer edge to the
    /// notch's, with the pill's own margin and gap at either end.
    public init(openIslandStripWidth stripWidth: Int, pill: CompactPillMetrics, spriteWidth: Int) {
        let edgeInset = Int(pill.edgeInset.rounded())
        let notchGap = Int(pill.slotSpacing.rounded())
        self.init(
            spriteWidth: spriteWidth,
            placeWidth: Int(pill.slotWidth.rounded()),
            flankWidth: max(stripWidth - edgeInset - notchGap, spriteWidth),
            edgeInset: edgeInset,
            notchGap: notchGap
        )
    }

    private init(spriteWidth: Int, placeWidth: Int, flankWidth: Int, edgeInset: Int, notchGap: Int) {
        self.spriteWidth = spriteWidth
        self.placeWidth = placeWidth
        self.flankWidth = flankWidth
        self.edgeInset = edgeInset
        self.notchGap = notchGap
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

    /// Just past the island's outer edge, where nothing of the pet is drawn.
    public var offstagePosition: Int {
        -(edgeInset + spriteWidth)
    }

    /// Everything the pet's view has to cover: the margin it walks out
    /// through, the flank, and the gap to the notch its effects may reach into.
    public var canvasWidth: Int {
        edgeInset + flankWidth + notchGap
    }
}
