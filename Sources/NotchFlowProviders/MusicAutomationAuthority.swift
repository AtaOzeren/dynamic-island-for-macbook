import AppKit
import Foundation
import NotchFlowCore
import os

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

    /// Runs an explicit user request without occupying the main actor while
    /// macOS displays or resolves its consent prompt.
    func requestWithoutBlocking(
        for target: MusicPlayerTarget
    ) async -> AutomationPermissionStatus

    /// Drops recorded status answers so a later read can observe a permission
    /// changed in System Settings while NotchFlow was inactive.
    func invalidateCachedStatuses()
}

public extension MusicAutomationAuthorizing {
    func invalidateCachedStatuses() {}
}

public extension Notification.Name {
    static let musicAutomationPermissionDidChange = Notification.Name(
        "com.notchflow.music-automation-permission-did-change"
    )
}

/// The real answer, from the Apple Events consent database.
///
/// `AEDeterminePermissionToAutomateTarget` is the only API that can report this
/// without side effects; the alternative — send an event and interpret the
/// failure — is precisely the launch-time prompt the permission flow forbids,
/// since the send is what triggers it.
@MainActor
public final class AppleEventsAutomationAuthority: MusicAutomationAuthorizing {
    typealias PermissionDeterminer = @Sendable (
        MusicPlayerTarget,
        Bool
    ) -> AutomationPermissionStatus
    typealias TargetRunningChecker = (MusicPlayerTarget) -> Bool
    typealias TargetPreparer = (MusicPlayerTarget) async -> Bool
    struct TargetEnvironment {
        let isRunning: TargetRunningChecker
        let prepare: TargetPreparer
    }

    private let permissionDeterminer: PermissionDeterminer
    private let targetEnvironment: TargetEnvironment
    private let cache = AutomationPermissionCache()
    private let permissionQueue = DispatchQueue(
        label: "com.notchflow.music-automation-permission",
        qos: .userInitiated
    )

    public convenience init() {
        self.init(
            determinePermission: { target, askUserIfNeeded in
                Self.determinePermission(for: target, askUserIfNeeded: askUserIfNeeded)
            },
            targetEnvironment: TargetEnvironment(
                isRunning: { Self.targetIsRunning($0) },
                prepare: { await Self.prepare($0) }
            )
        )
    }

    init(determinePermission: @escaping PermissionDeterminer) {
        self.permissionDeterminer = determinePermission
        targetEnvironment = TargetEnvironment(
            isRunning: { _ in true },
            prepare: { _ in true }
        )
    }

    init(
        determinePermission: @escaping PermissionDeterminer,
        targetEnvironment: TargetEnvironment
    ) {
        permissionDeterminer = determinePermission
        self.targetEnvironment = targetEnvironment
    }

    public func status(for target: MusicPlayerTarget) -> AutomationPermissionStatus {
        guard targetEnvironment.isRunning(target) else {
            return cache.completedStatus(for: target) ?? .notDetermined
        }
        let lookup = cache.lookup(for: target)
        guard let loading = lookup.loading else { return lookup.status }

        let cache = cache
        let permissionDeterminer = permissionDeterminer
        permissionQueue.async {
            let status = permissionDeterminer(target, false)
            guard cache.complete(status, for: loading) else { return }
            DistributedNotificationCenter.default().post(
                name: .musicAutomationPermissionDidChange,
                object: nil,
                userInfo: nil
            )
        }
        return lookup.status
    }

    public func request(for target: MusicPlayerTarget) -> AutomationPermissionStatus {
        let status = permissionDeterminer(target, true)
        storeExplicit(status, for: target)
        return status
    }

    public func requestWithoutBlocking(
        for target: MusicPlayerTarget
    ) async -> AutomationPermissionStatus {
        guard await targetEnvironment.prepare(target) else { return .notDetermined }
        let permissionDeterminer = permissionDeterminer
        let permissionQueue = permissionQueue
        let status = await withCheckedContinuation { continuation in
            permissionQueue.async {
                continuation.resume(returning: permissionDeterminer(target, true))
            }
        }
        storeExplicit(status, for: target)
        return status
    }

    public func invalidateCachedStatuses() {
        cache.invalidateCompletedStatuses()
    }

    private func storeExplicit(
        _ status: AutomationPermissionStatus,
        for target: MusicPlayerTarget
    ) {
        cache.storeExplicit(status, for: target)
        DistributedNotificationCenter.default().post(
            name: .musicAutomationPermissionDidChange,
            object: nil,
            userInfo: nil
        )
    }

    private static func targetIsRunning(_ target: MusicPlayerTarget) -> Bool {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: target.bundleIdentifier
        ).isEmpty == false
    }

    private static func prepare(_ target: MusicPlayerTarget) async -> Bool {
        guard targetIsRunning(target) == false else { return true }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: target.bundleIdentifier
        ) else { return false }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration
            ) { application, error in
                continuation.resume(returning: application != nil && error == nil)
            }
        }
    }

    /// Anything other than the three documented replies — most often
    /// `procNotFound`, because the target is not running and so cannot be asked
    /// about — is reported as `notDetermined`.
    ///
    /// That is the honest mapping rather than a convenient one: no decision has
    /// been recorded in those cases, and `notDetermined` is the state that keeps
    /// the feature offerable later without letting anything send an event now.
    private nonisolated static func determinePermission(
        for target: MusicPlayerTarget,
        askUserIfNeeded: Bool
    ) -> AutomationPermissionStatus {
        guard let processIdentifier = NSRunningApplication.runningApplications(
            withBundleIdentifier: target.bundleIdentifier
        ).first?.processIdentifier else { return .notDetermined }
        // Bundle-ID descriptors can wait forever while resolving Chromium apps
        // such as Spotify; the running process identifier addresses it exactly.
        let descriptor = targetDescriptor(processIdentifier: processIdentifier)
        guard let addressDescriptor = descriptor.aeDesc else { return .notDetermined }

        let result = AEDeterminePermissionToAutomateTarget(
            addressDescriptor,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            askUserIfNeeded
        )

        switch result {
        case OSStatus(noErr): return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        default: return .notDetermined
        }
    }

    nonisolated static func targetDescriptor(
        processIdentifier: pid_t
    ) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(processIdentifier: processIdentifier)
    }
}

private final class AutomationPermissionCache: Sendable {
    struct Loading: Sendable {
        let target: MusicPlayerTarget
        let token: UUID
    }

    struct Lookup: Sendable {
        let status: AutomationPermissionStatus
        let loading: Loading?
    }

    private struct State: Sendable {
        var statuses: [MusicPlayerTarget: AutomationPermissionStatus] = [:]
        var loadingTokens: [MusicPlayerTarget: UUID] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func completedStatus(
        for target: MusicPlayerTarget
    ) -> AutomationPermissionStatus? {
        state.withLock { $0.statuses[target] }
    }

    func lookup(for target: MusicPlayerTarget) -> Lookup {
        state.withLock { state in
            if let status = state.statuses[target] {
                return Lookup(status: status, loading: nil)
            }
            if state.loadingTokens[target] != nil {
                return Lookup(status: .notDetermined, loading: nil)
            }

            let token = UUID()
            state.loadingTokens[target] = token
            return Lookup(
                status: .notDetermined,
                loading: Loading(target: target, token: token)
            )
        }
    }

    func complete(
        _ status: AutomationPermissionStatus,
        for loading: Loading
    ) -> Bool {
        state.withLock { state in
            guard state.loadingTokens[loading.target] == loading.token else { return false }
            state.loadingTokens[loading.target] = nil
            state.statuses[loading.target] = status
            return true
        }
    }

    func storeExplicit(
        _ status: AutomationPermissionStatus,
        for target: MusicPlayerTarget
    ) {
        state.withLock { state in
            state.loadingTokens[target] = nil
            state.statuses[target] = status
        }
    }

    func invalidateCompletedStatuses() {
        state.withLock { $0.statuses.removeAll() }
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
    private var requestingTargets: Set<MusicPlayerTarget> = []

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

    public func reloadAccess() -> [MusicAutomationAccess] {
        authority.invalidateCachedStatuses()
        return access()
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
    public func isRequestInProgress(for target: MusicPlayerTarget) -> Bool {
        requestingTargets.contains(target)
    }

    @discardableResult
    public func requestAccess(
        for target: MusicPlayerTarget
    ) async -> MusicAutomationAccess {
        let access = access(for: target)
        guard access.isRequestable else { return access }
        guard requestingTargets.insert(target).inserted else { return access }
        defer { requestingTargets.remove(target) }

        explainedTargets.insert(target)
        let status = await authority.requestWithoutBlocking(for: target)
        return MusicAutomationAccess(target: target, status: status)
    }
}

extension AutomationPermissionStatus {
    fileprivate var isGranted: Bool { self == .granted }
}
