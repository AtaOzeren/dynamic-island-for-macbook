import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

@Suite("AIAgentInstance release fallback")
struct AIAgentInstanceReleaseFallbackTests {
    @Test(
        "drops an instance with no sessions",
        .enabled(
            if: !Self.assertionsAreEnabled,
            "assertionFailure traps the process when Swift assertions are enabled (debug builds); this release-only fallback path is only safely testable when assertions are compiled out"
        )
    )
    func emptyInstanceHasNoRepresentative() {
        let instance = AIAgentInstance(
            agentID: .opencode,
            rootSessionID: UUID(),
            sessions: []
        )

        #expect(instance == nil)
    }

    /// Swift assertions are enabled in debug builds (the default for `swift test`) and disabled in release builds.
    /// This property mirrors whether `assertionFailure` in the code under test will trap the process.
    #if DEBUG
    private static let assertionsAreEnabled = true
    #else
    private static let assertionsAreEnabled = false
    #endif
}
