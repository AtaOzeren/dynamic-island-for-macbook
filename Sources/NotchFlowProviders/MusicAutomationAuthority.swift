import AppKit
import Foundation
import NotchFlowCore

/// The seam between "what does the system say about automating this app" and
/// everything NotchFlow decides on top of that answer.
///
/// It exists for the same reason `MusicPlayerQuerying` does: the real
/// implementation is a TCC round-trip that can only be exercised on hardware,
/// with a consent database that a test cannot reset, while the sequencing rules
/// from `docs/09-security-privacy-permissions.md` — explain first, ask once,
/// never nag — must be verifiable in CI against a fake.
///
/// The split between `status` and `request` is the flow's step 2/step 3 boundary
/// made unavoidable: `status` promises never to show a system prompt, so it is
/// safe to call while merely rendering a settings row, and `request` is the only
/// member that can, so every prompt in NotchFlow has exactly one caller to audit.
@MainActor
public protocol MusicAutomationAuthorizing: AnyObject {
    /// The recorded decision. Never shows a prompt, never launches the target.
    func status(for target: MusicPlayerTarget) -> AutomationPermissionStatus

    /// Shows the system prompt if no decision is recorded, and answers with the
    /// decision that results. A target that was already granted or denied is
    /// answered from the record without a prompt.
    func request(for target: MusicPlayerTarget) -> AutomationPermissionStatus
}

/// The real answer, from the Apple Events consent database.
///
/// `AEDeterminePermissionToAutomateTarget` is the only API that can report this
/// without side effects; the alternative — send an event and interpret the
/// failure — is precisely the launch-time prompt the permission flow forbids,
/// since the send is what triggers it.
@MainActor
public final class AppleEventsAutomationAuthority: MusicAutomationAuthorizing {
    /// The consent database is keyed per target app, not per event, so the
    /// wildcard asks the question NotchFlow actually has: may we talk to this
    /// app at all. Naming a specific event would answer the same thing while
    /// implying a precision the system does not offer.
    private static let anyEventClass = AEEventClass(typeWildCard)
    private static let anyEventID = AEEventID(typeWildCard)

    /// `AEDeterminePermissionToAutomateTarget`'s documented replies. Spelled out
    /// rather than compared as raw numbers so the mapping below reads as the
    /// three-state answer it is.
    private static let permissionGranted = OSStatus(noErr)
    private static let permissionDenied = OSStatus(errAEEventNotPermitted)
    private static let consentNotYetGiven = OSStatus(errAEEventWouldRequireUserConsent)

    public init() {}

    public func status(for target: MusicPlayerTarget) -> AutomationPermissionStatus {
        determinePermission(for: target, askUserIfNeeded: false)
    }

    public func request(for target: MusicPlayerTarget) -> AutomationPermissionStatus {
        determinePermission(for: target, askUserIfNeeded: true)
    }

    /// Anything other than the three documented replies — most often
    /// `procNotFound`, because the target is not running and so cannot be asked
    /// about — is reported as `notDetermined`.
    ///
    /// That is the honest mapping rather than a convenient one: no decision has
    /// been recorded in those cases, and `notDetermined` is the state that keeps
    /// the feature offerable later without letting anything send an event now.
    private func determinePermission(
        for target: MusicPlayerTarget,
        askUserIfNeeded: Bool
    ) -> AutomationPermissionStatus {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: target.bundleIdentifier)
        guard let addressDescriptor = descriptor.aeDesc else { return .notDetermined }

        let result = AEDeterminePermissionToAutomateTarget(
            addressDescriptor,
            Self.anyEventClass,
            Self.anyEventID,
            askUserIfNeeded
        )

        switch result {
        case Self.permissionGranted: return .granted
        case Self.permissionDenied: return .denied
        case Self.consentNotYetGiven: return .notDetermined
        default: return .notDetermined
        }
    }
}

/// The permission flow of `docs/09-security-privacy-permissions.md`, as the one
/// thing standing between the music backend and an Apple Event.
///
/// Three rules live here, and nowhere else:
///
/// 1. **Explain before asking.** A target with no recorded decision is never
///    sent an event until `explainer` has shown NotchFlow's own account of what
///    is about to be requested and the user has agreed to be asked.
/// 2. **Ask once.** A target the user has been offered the explanation for is
///    not offered it again this launch, whatever they answered. Music apps post
///    their wake-up notification on every track change, so without this the
///    explanation would reappear on a beat — the nagging the flow rules out.
/// 3. **Denial is local.** A refused target answers `false` to `canQuery` and
///    the provider treats that exactly as "not playing", which is the graceful
///    degradation the acceptance criterion asks for: the other player, timers,
///    recording indicators and AI status are never consulted here at all.
@MainActor
public final class MusicAutomationGate {
    /// Shows NotchFlow's plain-language explanation and answers whether the user
    /// agreed to see the system prompt. Synchronous because the caller is about
    /// to decide whether to send an event, and a deferred answer would mean
    /// reporting "nothing playing" for a track the user is about to grant access
    /// to anyway.
    public typealias Explainer = (MusicAutomationAccess) -> Bool

    private let authority: any MusicAutomationAuthorizing
    private let explainer: Explainer
    private var explainedTargets: Set<MusicPlayerTarget> = []

    /// The default explainer refuses. A gate built without one is used by tests
    /// and by the Direct build, and in both cases silently opening a system
    /// prompt with no explanation would be the exact failure this type exists to
    /// prevent — so the safe answer is the one that costs nothing.
    public init(
        authority: any MusicAutomationAuthorizing = AppleEventsAutomationAuthority(),
        explainer: @escaping Explainer = { _ in false }
    ) {
        self.authority = authority
        self.explainer = explainer
    }

    public func access(for target: MusicPlayerTarget) -> MusicAutomationAccess {
        MusicAutomationAccess(target: target, status: authority.status(for: target))
    }

    public func access() -> [MusicAutomationAccess] {
        MusicPlayerTarget.allCases.map(access(for:))
    }

    /// Whether an Apple Event may be sent to this target right now, running the
    /// explain-then-ask sequence at most once if no decision is recorded.
    public func canQuery(_ target: MusicPlayerTarget) -> Bool {
        let access = access(for: target)
        guard access.isRequestable else { return access.canQuery }
        guard explainedTargets.insert(target).inserted else { return false }
        guard explainer(access) else { return false }
        return authority.request(for: target).isGranted
    }

    /// The settings row's path to the same prompt.
    ///
    /// It skips the explainer because the row already shows the explanation in
    /// place, and skips the ask-once record because the user pressed a button —
    /// a prompt the user asked for is the opposite of a nag.
    @discardableResult
    public func requestAccess(for target: MusicPlayerTarget) -> MusicAutomationAccess {
        explainedTargets.insert(target)
        return MusicAutomationAccess(target: target, status: authority.request(for: target))
    }
}

extension AutomationPermissionStatus {
    fileprivate var isGranted: Bool { self == .granted }
}
