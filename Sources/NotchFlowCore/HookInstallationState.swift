import Foundation

/// Whether an agent's configuration file currently carries NotchFlow's hook.
///
/// Deliberately distinct from `NotchFlowProviders.AgentInstallationStatus`,
/// which answers a different question: that type reports whether the *agent* is
/// on this machine (its config file exists at all), this one reports whether
/// *our hook* is inside that file. The AI Integrations pane needs both — an
/// agent can be installed with our hook absent, which is the only state where
/// offering an "Install" button makes sense.
///
/// Lives in Core rather than beside the installers that produce it because the
/// settings pane that renders it is in `NotchFlowUI`, which does not depend on
/// `NotchFlowProviders`. Core is the one module both sides already share, so
/// putting the vocabulary here is what lets the pane name a state without the
/// UI layer reaching into the provider layer.
///
/// Non-throwing by design. Every installer already surfaces typed errors from
/// `install()`/`uninstall()`, where the user asked for a mutation and deserves
/// to know why it failed. A read-only query has a truthful answer for every
/// input — including "this file is not something we can read" — so modelling
/// that as `configurationUnreadable` keeps call sites free of a `do/catch` that
/// would only ever map the error back into a display state.
public enum HookInstallationState: Equatable, Sendable {
    /// No configuration file at the path we would write to.
    case configurationMissing
    /// The file exists and is well-formed, but our hook is not in it.
    case hookAbsent
    /// The file exists and already carries exactly the hook we would write.
    case hookInstalled
    /// The file exists but cannot be parsed, so its hook state is unknowable.
    ///
    /// Distinct from `hookAbsent` because installing over an unreadable file
    /// would destroy user content the app never understood.
    case configurationUnreadable

    public var isInstalled: Bool {
        self == .hookInstalled
    }
}
