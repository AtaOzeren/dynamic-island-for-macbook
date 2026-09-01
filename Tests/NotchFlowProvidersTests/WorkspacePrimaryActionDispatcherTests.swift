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

    // MARK: - Telling one editor window from another

    /// An editor with several projects open is one application. Raising it lands
    /// on whichever window was last in front, so the agent's own folder has to
    /// travel with the host or the click goes to the wrong project.
    @Test("a host carries the folder its agent is running in")
    func hostCarriesTheAgentsFolder() {
        let resolver = AgentHostApplicationResolver(processes: [
            Self.process(pid: 100, ppid: 1, path: "/Applications/Visual Studio Code.app/Contents/MacOS/Code", bundle: "com.microsoft.VSCode"),
            Self.process(pid: 200, ppid: 100, path: "/bin/zsh"),
            Self.process(pid: 300, ppid: 200, path: "/usr/local/bin/opencode", cwd: "/Users/x/projects/alpha"),
        ])

        let hosts = resolver.hosts(for: .opencode)

        #expect(hosts.count == 1)
        #expect(hosts.first?.bundleIdentifier == "com.microsoft.VSCode")
        #expect(hosts.first?.workingDirectory == "/Users/x/projects/alpha")
    }

    /// Two windows of the same editor are one bundle identifier and two folders.
    /// The set of identifiers cannot separate them; the hosts can.
    @Test("two windows of one editor are two hosts sharing an identifier")
    func twoWindowsOfOneEditor() {
        let resolver = AgentHostApplicationResolver(processes: [
            Self.process(pid: 100, ppid: 1, path: "/Applications/Visual Studio Code.app/Contents/MacOS/Code", bundle: "com.microsoft.VSCode"),
            Self.process(pid: 200, ppid: 100, path: "/bin/zsh"),
            Self.process(pid: 300, ppid: 200, path: "/usr/local/bin/opencode", cwd: "/Users/x/projects/alpha"),
            Self.process(pid: 400, ppid: 100, path: "/bin/zsh"),
            Self.process(pid: 500, ppid: 400, path: "/usr/local/bin/opencode", cwd: "/Users/x/projects/beta"),
        ])

        let hosts = resolver.hosts(for: .opencode)
        let folders = Set(hosts.compactMap(\.workingDirectory))

        #expect(resolver.hostBundleIdentifiers(for: .opencode).count == 1)
        #expect(folders == ["/Users/x/projects/alpha", "/Users/x/projects/beta"])
    }

    /// A terminal has no folder-focusing URL, so nothing is lost by it being
    /// absent — the dispatcher falls back to activating the application.
    @Test("a host with no readable folder still resolves")
    func hostWithoutAFolderStillResolves() {
        let resolver = AgentHostApplicationResolver(processes: [
            Self.process(pid: 100, ppid: 1, path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", bundle: "com.apple.Terminal"),
            Self.process(pid: 200, ppid: 100, path: "/usr/local/bin/opencode"),
        ])

        let hosts = resolver.hosts(for: .opencode)

        #expect(hosts.first?.bundleIdentifier == "com.apple.Terminal")
        #expect(hosts.first?.workingDirectory == nil)
    }

    private static func process(
        pid: pid_t,
        ppid: pid_t,
        path: String,
        bundle: String? = nil,
        cwd: String? = nil
    ) -> WorkspaceProcessDescription {
        WorkspaceProcessDescription(
            processIdentifier: pid,
            parentProcessIdentifier: ppid,
            executableURL: URL(fileURLWithPath: path),
            applicationBundleIdentifier: bundle,
            workingDirectory: cwd
        )
    }
}
