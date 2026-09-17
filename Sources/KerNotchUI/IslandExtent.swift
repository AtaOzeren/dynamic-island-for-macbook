import CoreGraphics
import Foundation
import KerNotchCore

/// Everything that decides how big the island is drawn.
///
/// One value rather than eight arguments, because two places need the answer
/// and they must never disagree: the root view draws the island at this size,
/// and the presenter compares the size before a change with the size after it
/// to know which way the island is about to move.
public struct IslandExtentInput {
    public let state: PresentationState
    public let compact: CompactActivityPresentation
    /// Music icons already taken off the pill, which are not drawn and so do
    /// not widen it.
    public let hiddenMusicSlotIDs: Set<String>
    public let expanded: [any Activity]
    public let disclosedInstances: Set<ActivityIdentity>
    public let registrationTimes: [ActivityIdentity: Date]
    public let notchSize: CGSize
    public let layout: IslandLayout

    public init(
        state: PresentationState,
        compact: CompactActivityPresentation,
        hiddenMusicSlotIDs: Set<String>,
        expanded: [any Activity],
        disclosedInstances: Set<ActivityIdentity>,
        registrationTimes: [ActivityIdentity: Date],
        notchSize: CGSize,
        layout: IslandLayout
    ) {
        self.state = state
        self.compact = compact
        self.hiddenMusicSlotIDs = hiddenMusicSlotIDs
        self.expanded = expanded
        self.disclosedInstances = disclosedInstances
        self.registrationTimes = registrationTimes
        self.notchSize = notchSize
        self.layout = layout
    }
}

/// The compact pill's own geometry, whose flanks are only as wide as the slots
/// they carry.
public func islandCompactPillGeometry(_ input: IslandExtentInput) -> CompactPillGeometry {
    compactPillGeometry(
        for: compactSlotLayout(for: input.compact, hiding: input.hiddenMusicSlotIDs),
        notchSize: input.notchSize
    )
}

/// The connected silhouette, compact neck and expanded body alike.
///
/// The neck is the *balanced* pill width: the expanded shape draws it about its
/// own centre, so feeding it the asymmetric compact width would slide the
/// cutout off the hardware notch the moment the island opened.
public func islandConnectedGeometry(_ input: IslandExtentInput) -> ConnectedIslandGeometry {
    ConnectedIslandGeometry(
        compactSize: balancedCompactPillSize(
            for: compactSlotLayout(for: input.compact, hiding: input.hiddenMusicSlotIDs),
            notchSize: input.notchSize
        ),
        expandedContentSize: expandedPanelSize(
            for: input.expanded,
            disclosedInstances: input.disclosedInstances,
            registrationTimes: input.registrationTimes,
            notchSize: input.notchSize,
            metrics: input.layout.items,
            panelMetrics: input.layout.panel,
            topInset: input.notchSize.height
        )
    )
}

/// What the island currently is, surface and silhouette alike.
///
/// Both states allow for the outward top flare, so the drawn surface is one
/// flare wider than the content on each side.
public func islandSurfaceSize(_ input: IslandExtentInput) -> CGSize {
    input.state == .expanded
        ? islandConnectedGeometry(input).expandedSize
        : ConnectedIslandGeometry.compactSurfaceSize(
            forPillSize: islandCompactPillGeometry(input).size
        )
}
