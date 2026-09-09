import Foundation
import Testing

@testable import KerNotchCore
@testable import KerNotchProviders

@Test func testProvidersInitialization() {
    _ = KerNotchProviders()
    #expect(KerNotchCore.version == "1.0.0")
}
