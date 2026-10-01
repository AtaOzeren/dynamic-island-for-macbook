/// Receives the displays showing a full-screen Space, or switching to one, by
/// `DisplayDescription.identifier`, every time the set may have changed.
public typealias FullScreenDisplaysObserver = @MainActor (Set<String>) -> Void

/// The seam between hiding the island over full-screen apps and the window
/// server's record of which Space each display is showing. Production follows
/// Space switches as they happen; tests substitute a fake that reports on the
/// test's own schedule.
@MainActor
public protocol FullScreenSpaceObserving: AnyObject {
    /// Reports the current set at once, then again whenever a Space switch
    /// starts or ends and whenever the screen set changes.
    func startObserving(_ observer: @escaping FullScreenDisplaysObserver)
    func stopObserving()
}
