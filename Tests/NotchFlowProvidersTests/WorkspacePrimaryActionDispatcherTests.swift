import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowProviders

@Suite("Workspace primary action dispatcher")
struct WorkspacePrimaryActionDispatcherTests {
    @Test("traces an OpenCode CLI process to its VS Code host")
    func resolvesOpenCodeHostFromProcessAncestry() {
        let processes = [
            WorkspaceProcessDescription(
                processIdentifier: 30,
                parentProcessIdentifier: 20,
                executableURL: URL(fileURLWithPath: "/usr/local/bin/opencode"),
                applicationBundleIdentifier: nil
            ),
            WorkspaceProcessDescription(
                processIdentifier: 20,
                parentProcessIdentifier: 10,
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                applicationBundleIdentifier: nil
            ),
            WorkspaceProcessDescription(
                processIdentifier: 10,
                parentProcessIdentifier: 1,
                executableURL: URL(
                    fileURLWithPath: "/Applications/Visual Studio Code.app/Contents/MacOS/Code"
                ),
                applicationBundleIdentifier: "com.microsoft.VSCode"
            ),
        ]

        let hosts = AgentHostApplicationResolver(processes: processes)
            .hostBundleIdentifiers(for: .opencode)

        #expect(hosts == ["com.microsoft.VSCode"])
    }

    @Test("does not mistake an agent desktop helper for a CLI session")
    func ignoresAgentAppProcesses() {
        let processes = [
            WorkspaceProcessDescription(
                processIdentifier: 20,
                parentProcessIdentifier: 1,
                executableURL: URL(
                    fileURLWithPath: "/Applications/Codex.app/Contents/MacOS/Codex"
                ),
                applicationBundleIdentifier: "com.openai.codex"
            )
        ]

        let hosts = AgentHostApplicationResolver(processes: processes)
            .hostBundleIdentifiers(for: .codex)

        #expect(hosts.isEmpty)
    }

    @Test("chooses exact process host before an installed agent app")
    func exactProcessHostWins() {
        let resolver = AgentApplicationTargetResolver(
            processHostBundleIdentifiers: ["com.microsoft.VSCode"],
            workspace: WorkspaceApplicationSnapshot(
                frontmostBundleIdentifier: "com.microsoft.VSCode",
                runningBundleIdentifiers: ["com.microsoft.VSCode", "dev.opencode.app"]
            )
        )

        #expect(resolver.preferredRunningBundleIdentifier(for: .opencode) == "com.microsoft.VSCode")
    }

    @Test("falls back to the sole running terminal when the CLI already exited")
    func soleHostFallback() {
        let resolver = AgentApplicationTargetResolver(
            processHostBundleIdentifiers: [],
            workspace: WorkspaceApplicationSnapshot(
                frontmostBundleIdentifier: nil,
                runningBundleIdentifiers: ["com.apple.Terminal"]
            )
        )

        #expect(resolver.preferredRunningBundleIdentifier(for: .opencode) == "com.apple.Terminal")
    }

    @Test("does not guess between multiple unrelated running hosts")
    func ambiguousHostsDoNotJump() {
        let resolver = AgentApplicationTargetResolver(
            processHostBundleIdentifiers: [],
            workspace: WorkspaceApplicationSnapshot(
                frontmostBundleIdentifier: "com.apple.finder",
                runningBundleIdentifiers: ["com.apple.Terminal", "com.microsoft.VSCode"]
            )
        )

        #expect(resolver.preferredRunningBundleIdentifier(for: .opencode) == nil)
    }

    @Test("chooses the dedicated Claude desktop application")
    func dedicatedClaudeDesktopApplication() {
        let resolver = AgentApplicationTargetResolver(
            processHostBundleIdentifiers: [],
            workspace: WorkspaceApplicationSnapshot(
                frontmostBundleIdentifier: nil,
                runningBundleIdentifiers: ["com.anthropic.claudefordesktop"]
            )
        )

        #expect(
            resolver.preferredRunningBundleIdentifier(for: .claudeCode)
                == "com.anthropic.claudefordesktop"
        )
    }

    @Test("extracts the outer application from a nested helper bundle")
    func outerApplicationURL() {
        let executableURL = URL(
            fileURLWithPath:
                "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"
        )

        #expect(
            outermostApplicationBundleURL(for: executableURL)?.path
                == "/Applications/Visual Studio Code.app"
        )
    }
}
