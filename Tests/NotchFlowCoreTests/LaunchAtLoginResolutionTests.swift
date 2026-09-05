import ServiceManagement
import Testing

@testable import NotchFlowCore

@Suite("Launch-at-login resolution")
struct LaunchAtLoginResolutionTests {
    @Test("baseline: an enabled service already satisfies an enabled preference")
    func enabledPreferenceWithEnabledServiceNeedsNoAction() {
        #expect(
            resolveLaunchAtLogin(preference: true, serviceStatus: .enabled) == .none
        )
    }

    @Test("baseline: a disabled preference unregisters an enabled service")
    func disabledPreferenceWithEnabledServiceUnregisters() {
        #expect(
            resolveLaunchAtLogin(preference: false, serviceStatus: .enabled) == .unregister
        )
    }

    @Test("baseline: an enabled preference registers a missing service")
    func enabledPreferenceWithUnregisteredServiceRegisters() {
        #expect(
            resolveLaunchAtLogin(preference: true, serviceStatus: .notRegistered) == .register
        )
    }

    @Test("baseline: a disabled preference leaves a missing service alone")
    func disabledPreferenceWithUnregisteredServiceNeedsNoAction() {
        #expect(
            resolveLaunchAtLogin(preference: false, serviceStatus: .notRegistered) == .none
        )
    }

    @Test("an enabled preference reports required approval separately")
    func enabledPreferenceRequiringApprovalNeedsApproval() {
        #expect(
            resolveLaunchAtLogin(preference: true, serviceStatus: .requiresApproval)
                == .needsApproval
        )
    }

    @Test("a disabled preference unregisters a service awaiting approval")
    func disabledPreferenceRequiringApprovalUnregisters() {
        #expect(
            resolveLaunchAtLogin(preference: false, serviceStatus: .requiresApproval)
                == .unregister
        )
    }

    @Test("an enabled preference cannot register a service that is not found")
    func enabledPreferenceWithMissingServiceNeedsNoAction() {
        #expect(
            resolveLaunchAtLogin(preference: true, serviceStatus: .notFound) == .none
        )
    }

    @Test("a disabled preference leaves a missing service alone")
    func disabledPreferenceWithMissingServiceNeedsNoAction() {
        #expect(
            resolveLaunchAtLogin(preference: false, serviceStatus: .notFound) == .none
        )
    }
}
