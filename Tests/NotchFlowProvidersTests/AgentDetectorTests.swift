import Foundation
import Testing
@testable import NotchFlowCore
@testable import NotchFlowProviders

@Suite("AgentDetector")
struct AgentDetectorTests {
    private enum ProbeFailure: Error {
        case accessDenied
    }

    private static let homeDirectory = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    private static func detector(
        existingPaths: Set<String> = [],
        inaccessiblePaths: Set<String> = []
    ) -> AgentDetector {
        AgentDetector(homeDirectory: homeDirectory) { url in
            if inaccessiblePaths.contains(url.path) {
                throw ProbeFailure.accessDenied
            }
            return existingPaths.contains(url.path)
        }
    }

    @Test("detects each supported agent from its documented configuration path")
    func detectsInstalledAgents() {
        let detector = Self.detector(existingPaths: [
            "/Users/tester/.claude/settings.json",
            "/Users/tester/.codex/config.toml",
            "/Users/tester/.config/opencode/plugin"
        ])

        #expect(detector.detect() == [
            .claudeCode: .installed,
            .codex: .installed,
            .opencode: .installed
        ])
    }

    @Test("reports every supported agent as not installed when paths are missing")
    func reportsMissingAgents() {
        #expect(Self.detector().detect() == [
            .claudeCode: .notInstalled,
            .codex: .notInstalled,
            .opencode: .notInstalled
        ])
    }

    @Test("reports only the blocked agent as unknown")
    func reportsUnknownOnProbeFailure() {
        let detector = Self.detector(
            existingPaths: ["/Users/tester/.codex/config.toml"],
            inaccessiblePaths: ["/Users/tester/.claude/settings.json"]
        )

        #expect(detector.detect() == [
            .claudeCode: .unknown,
            .codex: .installed,
            .opencode: .notInstalled
        ])
    }

    @Test("returns exactly one result for every supported agent")
    func returnsCompleteMapping() {
        let result = Self.detector().detect()

        #expect(Set(result.keys) == Set(IPCAgentID.allCases))
        #expect(result.count == 3)
    }
}
