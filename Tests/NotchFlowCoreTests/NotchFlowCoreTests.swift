import Foundation
import Testing

@testable import NotchFlowCore

@Test func testCoreInitialization() {
    _ = NotchFlowCore()
    #expect(NotchFlowCore.version == "1.0.0")
}
