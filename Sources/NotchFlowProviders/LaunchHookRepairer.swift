import NotchFlowCore

@MainActor
public struct ManagedAgentHook {
    public let agentID: IPCAgentID
    private let readInstallationState: () -> HookInstallationState
    private let installHook: () throws -> Void
    private let uninstallHook: () throws -> Void

    public init(
        agentID: IPCAgentID,
        installationState: @escaping () -> HookInstallationState,
        install: @escaping () throws -> Void,
        uninstallManagedHook: @escaping () throws -> Void
    ) {
        self.agentID = agentID
        readInstallationState = installationState
        installHook = install
        uninstallHook = uninstallManagedHook
    }

    fileprivate var installationState: HookInstallationState {
        readInstallationState()
    }

    fileprivate func install() throws {
        try installHook()
    }

    fileprivate func uninstallManagedHook() throws {
        try uninstallHook()
    }
}

@MainActor
public struct LaunchHookRepairer {
    private let hooks: [ManagedAgentHook]

    public init(hooks: [ManagedAgentHook]) {
        self.hooks = hooks
    }

    public func repair(
        preferences: AIIntegrationPreferences,
        failureHandler: (IPCAgentID, any Error) -> Void
    ) {
        for hook in hooks {
            do {
                if preferences.isEnabled(hook.agentID) {
                    try repairEnabled(hook)
                } else {
                    try removeDisabled(hook)
                }
            } catch {
                failureHandler(hook.agentID, error)
            }
        }
    }

    private func repairEnabled(_ hook: ManagedAgentHook) throws {
        let state = hook.installationState
        guard state == .configurationMissing || state == .hookAbsent else { return }
        try hook.install()
    }

    private func removeDisabled(_ hook: ManagedAgentHook) throws {
        let state = hook.installationState
        guard state == .hookInstalled || state == .hookAbsent else { return }
        try hook.uninstallManagedHook()
    }
}
