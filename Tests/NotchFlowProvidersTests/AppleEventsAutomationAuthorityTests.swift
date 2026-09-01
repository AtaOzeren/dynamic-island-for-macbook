import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowProviders

@Suite("Apple Events automation authority")
@MainActor
struct AppleEventsAutomationAuthorityTests {
    @Test("status lookup never blocks the calling actor")
    func statusLookupIsAsynchronous() {
        let queryStarted = DispatchSemaphore(value: 0)
        let releaseQuery = DispatchSemaphore(value: 0)
        let authority = AppleEventsAutomationAuthority { _, askUserIfNeeded in
            #expect(askUserIfNeeded == false)
            queryStarted.signal()
            _ = releaseQuery.wait(timeout: .now() + .milliseconds(250))
            return .granted
        }
        let clock = ContinuousClock()
        let startedAt = clock.now

        let status = authority.status(for: .spotify)
        let elapsed = startedAt.duration(to: clock.now)

        #expect(status == .notDetermined)
        #expect(elapsed < .milliseconds(50))
        #expect(queryStarted.wait(timeout: .now() + .seconds(1)) == .success)
        releaseQuery.signal()
    }
}
