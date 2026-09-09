import Foundation
import Testing

@testable import KerNotchCore

@Test func testCoreInitialization() {
    _ = KerNotchCore()
    #expect(KerNotchCore.version == "1.0.0")
}
