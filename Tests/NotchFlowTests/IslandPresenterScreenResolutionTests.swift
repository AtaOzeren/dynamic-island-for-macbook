import Testing

@testable import NotchFlow
@testable import NotchFlowCore

/// A display identifier that is no longer in `NSScreen.screens` must resolve
/// to no screen at all — returning a stale or "best guess" screen here is what
/// placed the island at junk coordinates while displays were detaching.
@Suite("IslandPresenter screen resolution")
@MainActor
struct IslandPresenterScreenResolutionTests {
    @Test("a display identifier that is no longer attached resolves to no screen")
    func detachedIdentifierResolvesToNil() {
        #expect(IslandPresenter.screen(identifier: "detached-display-7C4F") == nil)
    }
}
