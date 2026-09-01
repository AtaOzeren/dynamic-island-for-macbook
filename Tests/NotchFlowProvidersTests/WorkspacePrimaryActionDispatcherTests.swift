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

    // MARK: - Evidence beats availability

    /// Running `opencode` in a VS Code terminal has to raise VS Code. An
    /// earlier ordering consulted the dedicated desktop app before the second
    /// and later process hosts, so the moment the same agent ran in two editors
    /// the click left both and launched an unrelated app.
    @Test("a live process host beats an installed dedicated app")
    func processHostBeatsDedicatedApplication() {
        let resolver = AgentApplicationTargetResolver(
            processHostBundleIdentifiers: ["com.microsoft.VSCode", "com.apple.Terminal"],
            workspace: WorkspaceApplicationSnapshot(
                frontmostBundleIdentifier: "com.apple.finder",
                runningBundleIdentifiers: [
                    "com.microsoft.VSCode",
                    "com.apple.Terminal",
                    "dev.opencode.app",
                ]
            )
        )

        let target = resolver.preferredRunningBundleIdentifier(for: .opencode)

        #expect(target != "dev.opencode.app")
        #expect(["com.microsoft.VSCode", "com.apple.Terminal"].contains(target))
    }

    /// A button that lands somewhere different on each press reads as broken,
    /// so an unresolved tie has to settle the same way every time.
    @Test("resolves a tie between process hosts the same way every time")
    func tiedProcessHostsResolveDeterministically() {
        let resolver = AgentApplicationTargetResolver(
            processHostBundleIdentifiers: ["com.microsoft.VSCode", "com.apple.Terminal"],
            workspace: WorkspaceApplicationSnapshot(
                frontmostBundleIdentifier: nil,
                runningBundleIdentifiers: ["com.microsoft.VSCode", "com.apple.Terminal"]
            )
        )

        let first = resolver.preferredRunningBundleIdentifier(for: .opencode)
        for _ in 0..<8 {
            #expect(resolver.preferredRunningBundleIdentifier(for: .opencode) == first)
        }
        #expect(first != nil)
    }

    /// The window the user was last looking at is the one the session was
    /// almost certainly started from.
    @Test("prefers the frontmost application among the process hosts")
    func frontmostProcessHostWins() {
        let resolver = AgentApplicationTargetResolver(
            processHostBundleIdentifiers: ["com.microsoft.VSCode", "com.apple.Terminal"],
            workspace: WorkspaceApplicationSnapshot(
                frontmostBundleIdentifier: "com.apple.Terminal",
                runningBundleIdentifiers: ["com.microsoft.VSCode", "com.apple.Terminal"]
            )
        )

        #expect(resolver.preferredRunningBundleIdentifier(for: .opencode) == "com.apple.Terminal")
    }

    /// Cursor's identifier carries a build-specific suffix, so it can only be
    /// recognised by prefix — listing one build literally goes stale.
    @Test("recognises Cursor as a development host")
    func cursorIsADevelopmentHost() {
        let cursor = "com.todesktop.230313mzl4w4u92"
        let resolver = AgentApplicationTargetResolver(
            processHostBundleIdentifiers: [],
            workspace: WorkspaceApplicationSnapshot(
                frontmostBundleIdentifier: nil,
                runningBundleIdentifiers: [cursor]
            )
        )

        #expect(resolver.preferredRunningBundleIdentifier(for: .claudeCode) == cursor)
    }
}
