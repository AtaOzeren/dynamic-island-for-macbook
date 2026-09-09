import SwiftUI

private struct IslandMotionSuspendedKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Whether the island is holding its continuous motion still.
    ///
    /// Set by the CPU watchdog's degrade action, never by the user. Views read
    /// it exactly as they read `accessibilityReduceMotion` and take the same
    /// resting branch, so degrading costs no second drawn state.
    var islandMotionSuspended: Bool {
        get { self[IslandMotionSuspendedKey.self] }
        set { self[IslandMotionSuspendedKey.self] = newValue }
    }
}
