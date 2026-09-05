import Foundation
import NotchFlowCore
import Testing

@testable import NotchFlowProviders

@Suite("Launch hook repair")
struct LaunchHookRepairerTests {
    @Test("removes a disabled managed hook and preserves an enabled managed hook")
    @MainActor
    func removesOnlyDisabledManagedHook() {
        let recorder = HookMutationRecorder()
        let repairer = LaunchHookRepairer(
            hooks: [
                .init(
                    agentID: .claudeCode,
                    installationState: { .hookInstalled },
                    install: { recorder.recordInstall(.claudeCode) },
                    uninstallManagedHook: { recorder.recordUninstall(.claudeCode) }
                ),
                .init(
                    agentID: .codex,
                    installationState: { .hookInstalled },
                    install: { recorder.recordInstall(.codex) },
                    uninstallManagedHook: { recorder.recordUninstall(.codex) }
                ),
            ]
        )

        repairer.repair(
            preferences: AIIntegrationPreferences(enabledAgentIDs: [.codex]),
            failureHandler: { _, error in
                Issue.record("Unexpected hook repair error: \(error)")
            }
        )

        #expect(recorder.installedAgentIDs.isEmpty)
        #expect(recorder.uninstalledAgentIDs == [.claudeCode])
    }

    @Test("does not ask an absent disabled hook to uninstall")
    @MainActor
    func skipsAbsentDisabledHook() {
        let recorder = HookMutationRecorder()
        let repairer = LaunchHookRepairer(
            hooks: [
                .init(
                    agentID: .opencode,
                    installationState: { .configurationMissing },
                    install: { recorder.recordInstall(.opencode) },
                    uninstallManagedHook: { recorder.recordUninstall(.opencode) }
                )
            ]
        )

        repairer.repair(
            preferences: AIIntegrationPreferences(),
            failureHandler: { _, error in
                Issue.record("Unexpected hook repair error: \(error)")
            }
        )

        #expect(recorder.installedAgentIDs.isEmpty)
        #expect(recorder.uninstalledAgentIDs.isEmpty)
    }
}

private final class HookMutationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var installed: [IPCAgentID] = []
    private var uninstalled: [IPCAgentID] = []

    var installedAgentIDs: [IPCAgentID] {
        lock.withLock { installed }
    }

    var uninstalledAgentIDs: [IPCAgentID] {
        lock.withLock { uninstalled }
    }

    func recordInstall(_ agentID: IPCAgentID) {
        lock.withLock { installed.append(agentID) }
    }

    func recordUninstall(_ agentID: IPCAgentID) {
        lock.withLock { uninstalled.append(agentID) }
    }
}
