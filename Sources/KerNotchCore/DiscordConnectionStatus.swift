/// Where the connection to the local Discord client stands, as the Integrations
/// pane reports it.
public enum DiscordConnectionStatus: Equatable, Sendable {
    /// The integration is off, or has no Client ID to connect with.
    case inactive
    /// Discord is not running, or not accepting connections yet.
    case discordUnavailable
    case connecting
    /// Discord answered, but KerNotch holds no authorization for it. Connecting
    /// is a user action, because it raises a prompt inside Discord.
    case needsAuthorization
    /// Discord is showing its authorization prompt.
    case awaitingApproval
    case connected(username: String?)
    case failed(DiscordConnectionFailure)

    /// Whether pressing Connect can start the authorization prompt right now.
    public var canAuthorize: Bool {
        switch self {
        case .needsAuthorization, .failed(.authorizationDenied), .failed(.authorizationFailed): true
        case .inactive, .discordUnavailable, .connecting, .awaitingApproval, .connected, .failed(.invalidClientID):
            false
        }
    }

    /// Whether starting the connection over is the way forward: every state
    /// that is waiting on Discord, or that Discord ended, rather than on the
    /// user.
    public var canReconnect: Bool {
        switch self {
        case .discordUnavailable, .connecting, .awaitingApproval, .failed(.invalidClientID): true
        case .inactive, .needsAuthorization, .connected, .failed(.authorizationDenied), .failed(.authorizationFailed):
            false
        }
    }
}

public enum DiscordConnectionFailure: Equatable, Sendable {
    /// Discord refused the handshake: the build's Client ID names no application.
    case invalidClientID
    /// The user declined the prompt inside Discord.
    case authorizationDenied
    /// Discord did not complete the connection. Before KerNotch's application is
    /// approved, this is what an account that is not one of its testers sees.
    case authorizationFailed
}
