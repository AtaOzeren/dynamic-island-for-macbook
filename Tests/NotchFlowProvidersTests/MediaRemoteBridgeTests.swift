import Foundation
import Testing
@testable import NotchFlowCore
@testable import NotchFlowProviders

@Suite("MediaRemoteBridge")
@MainActor
struct MediaRemoteBridgeTests {
    @Test("DefaultMediaRemoteBridge initializes and tears down safely")
    func initializesAndTearsDownSafely() {
        let bridge = DefaultMediaRemoteBridge()
        bridge.startObserving { _ in }
        bridge.stopObserving()
        bridge.stopObserving() // Idempotent
    }

    @Test("DefaultMediaRemoteBridge handles transport commands safely without throwing")
    func handlesTransportCommandsSafely() {
        let bridge = DefaultMediaRemoteBridge()
        bridge.send(.playPause)
        bridge.send(.nextTrack)
        bridge.send(.previousTrack)
    }
}
