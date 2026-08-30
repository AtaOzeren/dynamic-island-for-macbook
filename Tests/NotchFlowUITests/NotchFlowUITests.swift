import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

@Test func testUIInitialization() {
    _ = NotchFlowUI()
    #expect(NotchFlowCore.version == "1.0.0")
}
