import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowProviders

@Test func testProvidersInitialization() {
    _ = NotchFlowProviders()
    #expect(NotchFlowCore.version == "1.0.0")
}
