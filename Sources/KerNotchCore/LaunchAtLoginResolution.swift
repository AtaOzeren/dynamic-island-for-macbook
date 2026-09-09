import ServiceManagement

public enum LaunchAtLoginAction: Equatable, Sendable {
    case register
    case unregister
    case needsApproval
    case none
}

public func resolveLaunchAtLogin(
    preference: Bool,
    serviceStatus: SMAppService.Status
) -> LaunchAtLoginAction {
    switch (preference, serviceStatus) {
    case (true, .notRegistered): .register
    case (true, .requiresApproval): .needsApproval
    case (false, .enabled), (false, .requiresApproval): .unregister
    case (_, .enabled), (_, .notRegistered), (_, .notFound): .none
    @unknown default: .none
    }
}
