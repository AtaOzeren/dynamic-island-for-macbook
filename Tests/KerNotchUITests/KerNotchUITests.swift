import Foundation
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

@Test func testUIInitialization() {
    _ = KerNotchUI()
    #expect(KerNotchCore.version == "1.0.0")
}
