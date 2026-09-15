import Foundation
import Testing

@testable import KerNotch
@testable import KerNotchCore
@testable import KerNotchProviders
@testable import KerNotchUI

/// The hook the CPU watchdog degrades the island through.
///
/// Its one subtle obligation is that it borrows the *user's* reduced-motion
/// preference rather than replacing it: someone who had already forced Reduce
/// Motion on must not find it off because a watchdog episode ended.
@Suite("IslandPresenter degraded mode")
@MainActor
struct IslandPresenterDegradedModeTests {
    private static func presenter(
        reducedMotionOverride: Bool? = nil
    ) -> IslandPresenter {
        let store = SettingsStore(storage: DictionarySettingsStorage())
        store[.reducedMotionOverride] = reducedMotionOverride
        return IslandPresenter(manager: ActivityManager(), settingsStore: store)
    }

    @Test("suspends motion and forces reduced motion while degraded")
    func degradingSuspendsMotion() {
        let presenter = Self.presenter()

        presenter.enterDegradedMode()

        #expect(presenter.motionState.isDegraded)
        #expect(presenter.motionState.isMotionSuspended)
        #expect(presenter.motionState.reducedMotionOverride == true)
    }

    @Test("hands motion back to the system preference when the episode ends")
    func exitingRestoresFollowSystem() {
        let presenter = Self.presenter(reducedMotionOverride: nil)

        presenter.enterDegradedMode()
        presenter.exitDegradedMode()

        #expect(presenter.motionState.isDegraded == false)
        #expect(presenter.motionState.isMotionSuspended == false)
        #expect(presenter.motionState.reducedMotionOverride == nil)
    }

    @Test("leaves a user who had forced reduced motion on with it still on")
    func exitingKeepsAUserForcedReduceMotion() {
        let presenter = Self.presenter(reducedMotionOverride: true)

        presenter.enterDegradedMode()
        presenter.exitDegradedMode()

        #expect(presenter.motionState.reducedMotionOverride == true)
    }

    @Test("leaves a user who had forced reduced motion off with it still off")
    func exitingKeepsAUserForcedFullMotion() {
        let presenter = Self.presenter(reducedMotionOverride: false)

        presenter.enterDegradedMode()
        presenter.exitDegradedMode()

        #expect(presenter.motionState.reducedMotionOverride == false)
    }

    /// The escalation path degrades more than once per episode. A second call
    /// must not capture the override the first call installed, or exiting hands
    /// the user `true` forever.
    @Test("degrading twice still restores the user's own preference")
    func degradingIsIdempotent() {
        let presenter = Self.presenter(reducedMotionOverride: false)

        presenter.enterDegradedMode()
        presenter.enterDegradedMode()
        presenter.exitDegradedMode()

        #expect(presenter.motionState.reducedMotionOverride == false)
    }

    @Test("exiting without a preceding degrade changes nothing")
    func exitingWithoutDegradingIsANoOp() {
        let presenter = Self.presenter(reducedMotionOverride: true)
        let before = presenter.motionState

        presenter.exitDegradedMode()

        #expect(presenter.motionState == before)
    }

    /// Hover and click must survive a degrade. The island answering the pointer
    /// is what stops the user reading the degraded state as a crash, and mouse
    /// observing is tied to the panel being on screen.
    @Test("degrading never orders the island off screen")
    func degradingKeepsThePanelState() {
        let presenter = Self.presenter()
        let before = presenter.motionState.presentationState

        presenter.enterDegradedMode()

        #expect(presenter.motionState.presentationState == before)
    }
}

private final class DictionarySettingsStorage: SettingsStorage {
    private var values: [String: Any] = [:]
    private var registeredDefaults: [String: Any] = [:]

    func register(defaults: [String: Any]) {
        registeredDefaults.merge(defaults) { current, _ in current }
    }

    func object(forKey defaultName: String) -> Any? {
        values[defaultName] ?? registeredDefaults[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }

    func removeObject(forKey defaultName: String) {
        values.removeValue(forKey: defaultName)
    }
}
