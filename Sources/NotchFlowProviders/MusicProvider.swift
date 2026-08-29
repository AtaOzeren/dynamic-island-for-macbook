import NotchFlowCore

/// Called with the current now-playing state, or `nil` when nothing is playing
/// anywhere the backend can see.
public typealias NowPlayingObserver = @MainActor (NowPlaying?) -> Void

/// The seam between "however we learn about now-playing" and "how we turn that
/// into a `MusicActivity`", per `docs/06-activity-providers.md`.
///
/// Exactly one conformance is compiled into any given build — ScriptingBridge
/// for the App Store configuration (todo 42), MediaRemote for Direct (todo 43) —
/// and nothing above this protocol can tell which. Emissions are event-driven:
/// a conformance that polls violates the performance contract in
/// `docs/02-performance-contract.md`.
@MainActor
public protocol MusicProvider: AnyObject {
    /// The backend's user-visible name, surfaced in the about pane so a support
    /// conversation can establish which build is running (todo 44).
    var backendName: String { get }

    func startObserving(_ observer: @escaping NowPlayingObserver)
    func stopObserving()

    /// Sends a transport command to whatever is currently playing. A backend
    /// that cannot honour the command drops it rather than erroring: transport
    /// is best-effort, and a music activity is never worth an alert.
    func send(_ command: MusicTransportCommand)
}

/// Turns a now-playing emission into the activity the manager registers, or
/// `nil` when nothing is playing.
///
/// Split out of the provider so the mapping is testable without any backend at
/// all, and so both conformances share one definition of what an emission means
/// rather than each inventing its own.
public func musicActivity(for nowPlaying: NowPlaying?) -> MusicActivity? {
    guard let nowPlaying else { return nil }
    return MusicActivity(nowPlaying: nowPlaying)
}
