/// What a provider has to say about one activity: it is currently this, or it
/// is over.
///
/// Providers need both halves. The teardown rule in
/// `docs/06-activity-providers.md` is that a provider ends its activity when its
/// source goes quiet, and a channel that can only carry activities cannot say
/// "the music stopped" — the individual providers each solve this today by
/// emitting an optional and letting their single call site interpret `nil`.
/// Naming the end explicitly is what lets one registry multiplex every provider
/// onto one observer: with an optional it could see *that* something ended but
/// not *what*, since the identity it needed died with the value.
public enum ActivityEmission {
    case active(any Activity)
    case ended(ActivityIdentity)

    public var identity: ActivityIdentity {
        switch self {
        case .active(let activity): activity.identity
        case .ended(let identity): identity
        }
    }
}

public typealias ActivityObserver = @MainActor (ActivityEmission) -> Void

/// A source of activities that can be switched on and off.
///
/// `@MainActor` because every conformance observes a main-thread system source
/// and hands its result to the presentation layer; hoisting the isolation to the
/// protocol is what lets the registry start and stop them without hopping.
@MainActor
public protocol ActivityProvider: AnyObject {
    /// Which settings switch governs this provider.
    var identifier: ActivityProviderIdentifier { get }

    func startObserving(_ observer: @escaping ActivityObserver)
    func stopObserving()
}

/// Runs exactly the providers the user has switched on, and multiplexes them
/// onto one observer.
///
/// Enablement lives here rather than inside each provider because "am I allowed
/// to run" is the same question for all of them and none of them can answer it
/// from what they observe. A provider that read the setting itself would still
/// have to hold its system registration open to notice the setting change — the
/// observation this todo exists to stop.
///
/// The registry keeps only the identities of the activities each provider has
/// live, never the activities themselves: that is the minimum needed to end them
/// on disable, and holding the values instead would quietly make the registry a
/// second, staler copy of the manager's state.
@MainActor
public final class ActivityProviderRegistry {
    private let providers: [any ActivityProvider]
    private var enabledIdentifiers: Set<ActivityProviderIdentifier>
    private var liveIdentities: [ActivityProviderIdentifier: Set<ActivityIdentity>] = [:]
    private var observer: ActivityObserver?

    /// - Parameter enabledIdentifiers: the providers to run. Defaulting to all
    ///   of them keeps the registry out of the defaults business — the settings
    ///   store owns the documented defaults (todo 59), and a registry with its
    ///   own opinion about them would be a second place to change when they move.
    public init(
        providers: [any ActivityProvider],
        enabledIdentifiers: Set<ActivityProviderIdentifier> = Set(ActivityProviderIdentifier.allCases)
    ) {
        self.providers = providers
        self.enabledIdentifiers = enabledIdentifiers
    }

    public func isEnabled(_ identifier: ActivityProviderIdentifier) -> Bool {
        enabledIdentifiers.contains(identifier)
    }

    /// The providers observing right now. Reads as the acceptance criterion
    /// does: a disabled provider must not be in here.
    public var observingIdentifiers: Set<ActivityProviderIdentifier> {
        guard observer != nil else { return [] }
        return Set(providers.map(\.identifier)).intersection(enabledIdentifiers)
    }

    public func startObserving(_ observer: @escaping ActivityObserver) {
        stopObserving()
        self.observer = observer

        for provider in providers where isEnabled(provider.identifier) {
            start(provider)
        }
    }

    public func stopObserving() {
        guard observer != nil else { return }

        observer = nil
        liveIdentities.removeAll()

        for provider in providers {
            provider.stopObserving()
        }
    }

    /// Applies a settings change, taking effect on the call rather than on the
    /// next event: a provider switched off while its source is quiet must still
    /// stop observing immediately, and one whose source is *never* quiet would
    /// otherwise never notice.
    ///
    /// Disabling ends the provider's activities before stopping it, in that
    /// order. The reverse would strand them: a stopped provider has dropped the
    /// observer it would have ended them through, so the island would keep
    /// rendering a music card for a backend no longer watching anything.
    public func setEnabled(_ isEnabled: Bool, for identifier: ActivityProviderIdentifier) {
        guard self.isEnabled(identifier) != isEnabled else { return }

        if isEnabled {
            enabledIdentifiers.insert(identifier)
        } else {
            enabledIdentifiers.remove(identifier)
        }

        guard observer != nil else { return }

        for provider in providers where provider.identifier == identifier {
            if isEnabled {
                start(provider)
            } else {
                endLiveActivities(of: identifier)
                provider.stopObserving()
            }
        }
    }

    private func start(_ provider: any ActivityProvider) {
        let identifier = provider.identifier
        provider.startObserving { [weak self] emission in
            self?.receive(emission, from: identifier)
        }
    }

    /// A disabled provider's late emission is dropped rather than forwarded. The
    /// system sources are asynchronous, so one callback can already be in flight
    /// when the switch is thrown, and forwarding it would put back the very
    /// activity the disable just removed.
    private func receive(_ emission: ActivityEmission, from identifier: ActivityProviderIdentifier) {
        guard let observer, isEnabled(identifier) else { return }

        switch emission {
        case .active:
            liveIdentities[identifier, default: []].insert(emission.identity)
        case .ended:
            liveIdentities[identifier]?.remove(emission.identity)
        }

        observer(emission)
    }

    private func endLiveActivities(of identifier: ActivityProviderIdentifier) {
        guard let observer, let identities = liveIdentities.removeValue(forKey: identifier) else {
            return
        }

        for identity in identities {
            observer(.ended(identity))
        }
    }

    /// `isolated` so teardown can reach the providers at all: they are
    /// main-actor types, and a nonisolated `deinit` could only leave them
    /// observing into a closure whose `self` is already gone — a system
    /// registration held open with nobody at the other end.
    isolated deinit {
        for provider in providers {
            provider.stopObserving()
        }
    }
}
