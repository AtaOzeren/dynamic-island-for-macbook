import Foundation

/// Why an agent's turn ended in `error`.
///
/// A closed vocabulary rather than the provider's own message, for three
/// reasons that all point the same way:
///
/// - The island localises what it draws. "Kota doldu" cannot be produced by a
///   hook script that has no idea what language the user reads.
/// - `IPCMessageValidator` rejects the characters provider errors are full of —
///   `[glm/glm-5.2] [429]` carries brackets from the forbidden set — so passing
///   the raw text through would drop the whole message and report nothing at
///   all, which is the failure mode this type exists to prevent.
/// - The privacy rule in `docs/07-ai-integration.md` keeps prompts, code and
///   transcripts off the screen. A fixed set of causes cannot smuggle any of
///   them; a free-text field can.
///
/// The cases are the ones a user can act on, not the ones an HTTP status can
/// distinguish: 401 and 403 are one problem to whoever has to fix it.
public enum AIAgentFailureReason: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    /// The account is out of quota, credits, or rate-limit budget. The one case
    /// that resolves itself, given time — hence `retryAt`.
    case quotaExhausted
    /// Credentials are missing, invalid, or not permitted for this account.
    case authFailed
    /// The provider is overloaded or erroring on its own side.
    case providerUnavailable
    /// The request itself was refused: malformed, unsupported model, over the
    /// output ceiling.
    case requestRejected
    /// A failure we could not classify. Still an error, still red — only
    /// unnamed.
    case unknown

    /// Whether the condition lifts on its own rather than needing the user to
    /// change something.
    ///
    /// Only quota does. It is also the only one worth telling the user to wait
    /// for, which is why the island shows a reset time for it and not for the
    /// others.
    public var resolvesWithTime: Bool { self == .quotaExhausted }
}
