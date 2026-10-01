import CoreGraphics
import SwiftUI

private struct IslandHoverScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// How much the island is scaled up right now for the hover peek, `1` when
    /// it is not.
    ///
    /// Published for what must not scale with the island: the pet's pixel art
    /// is drawn one image pixel per device pixel, and any other scale resamples
    /// it — at the peek's 3%, a stray column or row doubled somewhere in the
    /// dog. Glyphs and shapes are vectors and scale cleanly, so nothing else
    /// reads this.
    public var islandHoverScale: CGFloat {
        get { self[IslandHoverScaleKey.self] }
        set { self[IslandHoverScaleKey.self] = newValue }
    }
}

/// The scale that cancels the island's hover peek for `islandScale`, so what
/// carries it stays at its own size while riding the peek's movement.
func islandPeekCounterScale(for islandScale: CGFloat) -> CGFloat {
    guard islandScale > 0 else { return 1 }
    return 1 / islandScale
}
