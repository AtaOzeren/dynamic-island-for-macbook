import AppKit
import Darwin
import Foundation
import NotchFlowCore

struct WorkspaceProcessDescription: Equatable, Sendable {
    let processIdentifier: pid_t
    let parentProcessIdentifier: pid_t
    let executableURL: URL
    let applicationBundleIdentifier: String?
}

struct AgentHostApplicationResolver {
    let processes: [WorkspaceProcessDescription]

    func hostBundleIdentifiers(for agent: IPCAgentID) -> Set<String> {
        let processesByID = Dictionary(uniqueKeysWithValues: processes.map { ($0.processIdentifier, $0) })
        let executableNames = Self.executableNames(for: agent)

        return Set(
            processes.compactMap { process in
                guard process.applicationBundleIdentifier == nil else { return nil }
                guard executableNames.contains(process.executableURL.lastPathComponent.lowercased()) else {
                    return nil
                }
                return hostBundleIdentifier(for: process, processesByID: processesByID)
            }
        )
    }

    private func hostBundleIdentifier(
        for process: WorkspaceProcessDescription,
        processesByID: [pid_t: WorkspaceProcessDescription]
    ) -> String? {
        var parentProcessIdentifier = process.parentProcessIdentifier
        var visitedProcessIdentifiers: Set<pid_t> = []

        while parentProcessIdentifier > 1,
            visitedProcessIdentifiers.insert(parentProcessIdentifier).inserted,
            let parent = processesByID[parentProcessIdentifier]
        {
            if let bundleIdentifier = parent.applicationBundleIdentifier {
                return bundleIdentifier
            }
            parentProcessIdentifier = parent.parentProcessIdentifier
        }
        return nil
    }

    private static func executableNames(for agent: IPCAgentID) -> Set<String> {
        switch agent {
        case .claudeCode: ["claude"]
        case .codex: ["codex"]
        case .opencode: ["opencode", "opencode.exe"]
        }
    }
}

struct WorkspaceApplicationSnapshot: Equatable, Sendable {
    let frontmostBundleIdentifier: String?
    let runningBundleIdentifiers: Set<String>
}

struct AgentApplicationTargetResolver {
    let processHostBundleIdentifiers: Set<String>
    let workspace: WorkspaceApplicationSnapshot

    /// Where clicking this agent's row should take the user.
    ///
    /// An application that is *actually hosting a live process* for this agent
    /// always beats one that merely could be: running `opencode` in a VS Code
    /// terminal has to raise VS Code, not launch the OpenCode desktop app that
    /// has nothing to do with the session on screen. An earlier ordering
    /// consulted the dedicated app before the second and later process hosts,
    /// so the moment the same agent ran in two editors the click left both.
    func preferredRunningBundleIdentifier(for agent: IPCAgentID) -> String? {
        let runningProcessHosts = processHostBundleIdentifiers.intersection(
            workspace.runningBundleIdentifiers
        )
        if let host = hostRunningTheAgent(among: runningProcessHosts) {
            return host
        }

        if let dedicated = dedicatedBundleIdentifiers(for: agent).first(where: {
            workspace.runningBundleIdentifiers.contains($0)
        }) {
            return dedicated
        }

        return soleDevelopmentHost()
    }

    /// One of the applications actually hosting a live process for this agent.
    ///
    /// Every candidate here is evidenced by the process tree, so picking one is
    /// never a guess about *whether* the agent is there — only about which of
    /// its several homes to raise. The frontmost wins, because that is the
    /// window the user was last looking at; otherwise a development host beats
    /// an incidental parent, and a stable sort settles the rest. Determinism
    /// matters more than the particular winner: a button that lands somewhere
    /// different on each press reads as broken.
    private func hostRunningTheAgent(among candidates: Set<String>) -> String? {
        guard candidates.isEmpty == false else { return nil }
        if let frontmost = workspace.frontmostBundleIdentifier,
            candidates.contains(frontmost)
        {
            return frontmost
        }
        if candidates.count == 1 {
            return candidates.first
        }

        let developmentHosts = candidates.filter(Self.isDevelopmentHost)
        return (developmentHosts.isEmpty ? candidates : developmentHosts).min()
    }

    /// The last resort, used when nothing links the agent to any application.
    ///
    /// Deliberately refuses to choose between several: with no evidence at all,
    /// one running editor is a reasonable inference and two is a coin toss, and
    /// jumping the user into the wrong window is worse than doing nothing.
    private func soleDevelopmentHost() -> String? {
        let runningHosts = workspace.runningBundleIdentifiers.filter(Self.isDevelopmentHost)
        if let frontmost = workspace.frontmostBundleIdentifier,
            runningHosts.contains(frontmost)
        {
            return frontmost
        }
        return runningHosts.count == 1 ? runningHosts.first : nil
    }

    func dedicatedBundleIdentifiers(for agent: IPCAgentID) -> [String] {
        switch agent {
        case .claudeCode: ["com.anthropic.claudefordesktop"]
        case .codex: ["com.openai.codex", "com.openai.chat"]
        case .opencode: ["dev.opencode.app"]
        }
    }

    private static func isDevelopmentHost(_ bundleIdentifier: String) -> Bool {
        knownDevelopmentHostBundleIdentifiers.contains(bundleIdentifier)
            || developmentHostBundlePrefixes.contains { bundleIdentifier.hasPrefix($0) }
    }

    /// Vendors that ship a family of identifiers rather than one.
    ///
    /// `com.todesktop.` covers Cursor, whose identifier carries a build-specific
    /// suffix and therefore cannot be listed literally without going stale.
    private static let developmentHostBundlePrefixes = [
        "com.jetbrains.",
        "com.todesktop.",
    ]

    private static let knownDevelopmentHostBundleIdentifiers: Set<String> = [
        "co.zeit.hyper",
        "com.apple.Terminal",
        "com.apple.dt.Xcode",
        "com.exafunction.windsurf",
        "com.github.wez.wezterm",
        "com.google.antigravity-ide",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.mitchellh.ghostty",
        "com.qvacua.VimR",
        "com.raggi.rio",
        "com.trae.app",
        "com.vscodium",
        "dev.warp.Warp",
        "dev.warp.Warp-Stable",
        "dev.zed.Zed",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "org.tabby",
        "org.vim.MacVim",
    ]
}

func outermostApplicationBundleURL(for executableURL: URL) -> URL? {
    var directory = executableURL.deletingLastPathComponent()
    var outermostApplicationURL: URL?

    while directory.path != "/" {
        if directory.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            outermostApplicationURL = directory
        }
        directory.deleteLastPathComponent()
    }
    return outermostApplicationURL
}

private struct SystemWorkspaceProcessScanner {
    func processes() -> [WorkspaceProcessDescription] {
        let estimatedProcessCount = max(Int(proc_listallpids(nil, 0)), 0)
        var processIdentifiers = [pid_t](repeating: 0, count: estimatedProcessCount + 64)
        let processCount = processIdentifiers.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }

        return processIdentifiers.prefix(max(Int(processCount), 0)).compactMap(processDescription)
    }

    private func processDescription(_ processIdentifier: pid_t) -> WorkspaceProcessDescription? {
        guard processIdentifier > 1 else { return nil }

        var processInfo = proc_bsdinfo()
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard
            proc_pidinfo(
                processIdentifier,
                PROC_PIDTBSDINFO,
                0,
                &processInfo,
                infoSize
            ) == infoSize
        else {
            return nil
        }

        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(processIdentifier, &pathBuffer, UInt32(pathBuffer.count)) > 0 else {
            return nil
        }
        let pathBytes = pathBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let executableURL = URL(
            fileURLWithPath: String(decoding: pathBytes, as: UTF8.self)
        )
        let applicationBundleIdentifier = outermostApplicationBundleURL(for: executableURL)
            .flatMap(Bundle.init(url:))?
            .bundleIdentifier

        return WorkspaceProcessDescription(
            processIdentifier: processIdentifier,
            parentProcessIdentifier: pid_t(processInfo.pbi_ppid),
            executableURL: executableURL,
            applicationBundleIdentifier: applicationBundleIdentifier
        )
    }
}

/// Executes a `PrimaryAction.Intent` that acts on the wider system.
///
/// Timer intents are deliberately absent: they are routing, not system calls —
/// the composition root sends them to `TimerProvider.handle(_:)` exactly as the
/// timer view's own controls do, and a second execution path would be a second
/// chance for the two to disagree about what a pause means.
@MainActor
public protocol PrimaryActionDispatching: AnyObject {
    /// Performs the intent. Returns whether something was activated — `false`
    /// means the target is not running and no installed application matched,
    /// which the caller may surface rather than swallow.
    @discardableResult
    func perform(_ intent: PrimaryAction.Intent) -> Bool
}

/// The production executor: activates an application through `NSWorkspace`.
///
/// Music resolves by reported application name. Agent actions first trace a
/// live CLI process to its parent editor or terminal, then use deterministic
/// running-host and installed-app fallbacks.
@MainActor
public final class WorkspacePrimaryActionDispatcher: PrimaryActionDispatching {
    /// Where a name lookup has to become a bundle identifier. Only the players
    /// the app actually names in activities belong here; an unknown name has
    /// no entry and the intent resolves to a handled failure.
    private static let bundleIdentifiersByName = [
        "Spotify": "com.spotify.client",
        "Music": "com.apple.Music",
        "Apple Music": "com.apple.Music",
        "Claude": "com.anthropic.claudefordesktop",
        "Claude Code": "com.anthropic.claudefordesktop",
        "Codex": "com.openai.chat",
        "OpenCode": "dev.opencode.app",
    ]

    public init() {}

    public func perform(_ intent: PrimaryAction.Intent) -> Bool {
        switch intent {
        case .openApplicationNamed(let name):
            return activateApplication(named: name)
        case .openAgentApplication(let agent):
            return activateAgentApplication(agent)
        case .stopTimer, .pauseTimer, .resumeTimer:
            return false
        }
    }

    private func activateAgentApplication(_ agent: IPCAgentID) -> Bool {
        let workspace = NSWorkspace.shared
        let runningApplications = workspace.runningApplications
        let processHosts = AgentHostApplicationResolver(
            processes: SystemWorkspaceProcessScanner().processes()
        ).hostBundleIdentifiers(for: agent)
        let resolver = AgentApplicationTargetResolver(
            processHostBundleIdentifiers: processHosts,
            workspace: WorkspaceApplicationSnapshot(
                frontmostBundleIdentifier: workspace.frontmostApplication?.bundleIdentifier,
                runningBundleIdentifiers: Set(runningApplications.compactMap(\.bundleIdentifier))
            )
        )

        if let bundleIdentifier = resolver.preferredRunningBundleIdentifier(for: agent),
            let running = runningApplications.first(where: {
                $0.bundleIdentifier == bundleIdentifier && $0.activationPolicy == .regular
            })
        {
            return activate(running, in: workspace)
        }

        for bundleIdentifier in resolver.dedicatedBundleIdentifiers(for: agent) {
            guard let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                continue
            }
            return workspace.open(url)
        }
        return false
    }

    private func activateApplication(named name: String) -> Bool {
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == name && $0.activationPolicy == .regular
        }) {
            return activate(running, in: NSWorkspace.shared)
        }

        guard
            let bundleIdentifier = Self.bundleIdentifiersByName[name],
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            return false
        }
        // The synchronous `open(_:)` rather than the async `openApplication`:
        // the click's result must be knowable at the call site, and launching
        // an app URL is the one operation `open` answers honestly with a Bool.
        return NSWorkspace.shared.open(url)
    }

    private func activate(_ application: NSRunningApplication, in workspace: NSWorkspace) -> Bool {
        if application.activate(options: [.activateAllWindows]) {
            return true
        }
        guard
            let url = application.bundleURL
                ?? application.bundleIdentifier.flatMap(workspace.urlForApplication)
        else {
            return false
        }
        return workspace.open(url)
    }
}
