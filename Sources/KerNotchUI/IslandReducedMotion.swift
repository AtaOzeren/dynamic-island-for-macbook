import SwiftUI

private struct IslandReducedMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// KerNotch's own Motion choice from the General pane: `true` always
    /// reduces, `false` never does, `nil` follows the system.
    ///
    /// Carried separately from `accessibilityReduceMotion`, which SwiftUI
    /// fills from the system setting alone, so a view that honours the user's
    /// choice reads both — see `islandReducesMotion(system:override:)`.
    public var islandReducedMotionOverride: Bool? {
        get { self[IslandReducedMotionOverrideKey.self] }
        set { self[IslandReducedMotionOverrideKey.self] = newValue }
    }

    /// Whether the island's motion is reduced: KerNotch's own Motion choice
    /// where the user made one, the system's Reduce Motion otherwise.
    ///
    /// Every island view reads this rather than `accessibilityReduceMotion`.
    /// Reading the system value alone, "Always reduce" in General only changed
    /// the transitions' curves while the equaliser, the glow and the agent's
    /// working dot kept moving — and "Never reduce" stood them still anyway.
    public var prefersReducedIslandMotion: Bool {
        islandReducesMotion(system: accessibilityReduceMotion, override: islandReducedMotionOverride)
    }
}

/// Whether motion is reduced once KerNotch's own choice is applied over the
/// system's: the explicit choice wins, and without one the system decides.
func islandReducesMotion(system: Bool, override: Bool?) -> Bool {
    override ?? system
}
