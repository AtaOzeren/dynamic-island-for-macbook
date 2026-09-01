import AppKit
import Darwin
import Foundation
import NotchFlowCore

struct WorkspaceProcessDescription: Equatable, Sendable {
    let processIdentifier: pid_t
    let parentProcessIdentifier: pid_t
    let executableURL: URL
    let applicationBundleIdentifier: String?
    /// The directory the process is running in, when it could be read.
    ///
    /// This is what tells one editor *window* from another. An editor with three
    /// projects open is one application with one bundle identifier, so raising
    /// the application alone lands on whichever window happens to be in front —
    /// which is exactly the window the user was not looking for.
    var workingDirectory: String?
}

/// One live agent process and the application hosting it.
struct AgentHost: Equatable, Sendable {
    let bundleIdentifier: String
    let workingDirectory: String?
}

struct AgentHostApplicationResolver {
    let processes: [WorkspaceProcessDescription]

    func hosts(for agent: IPCAgentID) -> [AgentHost] {
        let processesByID = Dictionary(uniqueKeysWithValues: processes.map { ($0.processIdentifier, $0) })
        let executableNames = Self.executableNames(for: agent)

        return processes.compactMap { process in
            guard process.applicationBundleIdentifier == nil else { return nil }
            guard executableNames.contains(process.executableURL.lastPathComponent.lowercased()) else {
                return nil
            }
            guard
                let bundleIdentifier = hostBundleIdentifier(
                    for: process,
                    processesByID: processesByID
                )
            else {
                return nil
            }
            return AgentHost(
                bundleIdentifier: bundleIdentifier,
                workingDirectory: process.workingDirectory
            )
        }
    }

    func hostBundleIdentifiers(for agent: IPCAgentID) -> Set<String> {
        Set(hosts(for: agent).map(\.bundleIdentifier))
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
            applicationBundleIdentifier: applicationBundleIdentifier,
            workingDirectory: Self.workingDirectory(of: processIdentifier)
        )
    }

    /// The process's current directory.
    ///
    /// Read from the kernel rather than from the message the agent sent: the IPC
    /// envelope carries no path, and `docs/07-ai-integration.md` is emphatic that
    /// it must not start. This asks the same question of the operating system
    /// instead, needs no permission, and returns nothing for a process the user
    /// does not own.
    private static func workingDirectory(of processIdentifier: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(processIdentifier, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else {
            return nil
        }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        return path.isEmpty ? nil : path
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

    /// Editors that can be asked to bring forward the window already holding a
    /// folder, by opening a URL that names it.
    ///
    /// This is the only way to tell one window of an editor from another without
    /// the Accessibility or Screen Recording permission: an editor is one
    /// application whatever it has open, so activating it raises whichever
    /// window was last in front. Terminals have no equivalent and fall back to
    /// being activated.
    private static let folderURLSchemesByBundleIdentifier = [
        "com.microsoft.VSCode": "vscode",
        "com.microsoft.VSCodeInsiders": "vscode-insiders",
        "com.vscodium": "vscodium",
        "com.exafunction.windsurf": "windsurf",
        "com.google.antigravity-ide": "antigravity",
        "com.trae.app": "trae",
        "dev.zed.Zed": "zed",
    ]

    /// Cursor ships a build-specific identifier, so it is matched by prefix.
    private static let folderURLSchemesByBundlePrefix = [
        "com.todesktop.": "cursor"
    ]

    private static func folderURLScheme(for bundleIdentifier: String) -> String? {
        if let scheme = folderURLSchemesByBundleIdentifier[bundleIdentifier] {
            return scheme
        }
        return folderURLSchemesByBundlePrefix
            .first { bundleIdentifier.hasPrefix($0.key) }?
            .value
    }

    /// Raises the window already holding `directory`, when the host can do that.
    ///
    /// The scheme's registered handler is checked against the host we resolved
    /// before the URL is opened: an unrelated application that claimed the
    /// scheme would otherwise be launched instead of the editor the agent is
    /// actually running in.
    private func activateWindow(
        holding directory: String,
        in bundleIdentifier: String,
        workspace: NSWorkspace
    ) -> Bool {
        guard
            let scheme = Self.folderURLScheme(for: bundleIdentifier),
            var components = URLComponents(string: "\(scheme)://file")
        else {
            return false
        }
        components.path = directory
        guard
            let url = components.url,
            let handler = workspace.urlForApplication(toOpen: url),
            Bundle(url: handler)?.bundleIdentifier == bundleIdentifier
        else {
            return false
        }
        return workspace.open(url)
    }

    private func activateAgentApplication(_ agent: IPCAgentID) -> Bool {
        let workspace = NSWorkspace.shared
        let runningApplications = workspace.runningApplications
        let hosts = AgentHostApplicationResolver(
            processes: SystemWorkspaceProcessScanner().processes()
        ).hosts(for: agent)
        let processHosts = Set(hosts.map(\.bundleIdentifier))
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
            // The agent's own folder first, so a click lands on the window it is
            // running in rather than on whichever window of that editor happened
            // to be in front.
            if let directory = hosts.first(where: { $0.bundleIdentifier == bundleIdentifier })?
                .workingDirectory,
                activateWindow(holding: directory, in: bundleIdentifier, workspace: workspace)
            {
                return true
            }
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
