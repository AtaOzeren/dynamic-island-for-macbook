import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowProviders

/// Todo 57's acceptance criterion: the snippet the manual-setup UI shows is the
/// text the installer would have written. Every test here proves it the same
/// way — install into an in-memory file system, then compare the fallback's
/// snippet against the bytes that landed on disk — so a future change that
/// re-derives the snippet anywhere else fails here.
@Suite("ManualSetupInstructions")
struct ManualSetupInstructionsTests {
    private static let homeDirectory = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    // MARK: - Snippet equals what the installer writes

    @Test("Claude Code's snippet is the settings file the installer writes")
    func claudeCodeSnippetMatchesInstalledFile() throws {
        let fileSystem = InMemoryManualSetupFileSystem()
        let installer = ClaudeCodeHookInstaller(
            homeDirectory: Self.homeDirectory,
            fileSystem: fileSystem
        )
        let settingsURL = Self.homeDirectory.appending(path: ".claude/settings.json")

        let instructions = try installer.manualSetupInstructions()
        let proposed = try installer.proposedSettings()
        try installer.install()

        #expect(instructions.snippet == proposed)
        #expect(instructions.snippet == fileSystem.text(at: settingsURL))
        #expect(instructions.destinationPath == settingsURL.path)
        #expect(instructions.agent == .claudeCode)
    }

    @Test("Codex's snippet is the configuration the installer writes")
    func codexSnippetMatchesInstalledFile() throws {
        let fileSystem = InMemoryManualSetupFileSystem()
        let installer = CodexHookInstaller(
            homeDirectory: Self.homeDirectory,
            fileSystem: fileSystem
        )
        let configURL = Self.homeDirectory.appending(path: ".codex/config.toml")

        let instructions = try installer.manualSetupInstructions()
        let proposed = try installer.proposedConfiguration()
        try installer.install()

        #expect(instructions.snippet == proposed)
        #expect(instructions.snippet == fileSystem.text(at: configURL))
        #expect(instructions.destinationPath == configURL.path)
        #expect(instructions.agent == .codex)
    }

    @Test("OpenCode's snippet is the plugin file the installer writes")
    func openCodeSnippetMatchesInstalledFile() throws {
        let fileSystem = InMemoryManualSetupFileSystem()
        let installer = OpenCodePluginInstaller(
            homeDirectory: Self.homeDirectory,
            fileSystem: fileSystem
        )
        let pluginURL = Self.homeDirectory.appending(
            path: ".config/opencode/plugins/notchflow.ts"
        )

        let instructions = try installer.manualSetupInstructions()
        let proposed = try installer.proposedPlugin()
        try installer.install()

        #expect(instructions.snippet == proposed)
        #expect(instructions.snippet == fileSystem.text(at: pluginURL))
        #expect(instructions.destinationPath == pluginURL.path)
        #expect(instructions.agent == .opencode)
    }

    /// The interesting case for the two merging installers: with a settings file
    /// already on disk, the snippet has to carry the user's own keys too, or a
    /// user who follows the instructions loses them.
    @Test("Claude Code's snippet carries the user's existing settings")
    func claudeCodeSnippetPreservesExistingSettings() throws {
        let settingsURL = Self.homeDirectory.appending(path: ".claude/settings.json")
        let existing = Data(#"{"theme":"dark"}"#.utf8)
        let fileSystem = InMemoryManualSetupFileSystem(files: [settingsURL: existing])
        let installer = ClaudeCodeHookInstaller(
            homeDirectory: Self.homeDirectory,
            fileSystem: fileSystem
        )

        let instructions = try installer.manualSetupInstructions()
        try installer.install()

        #expect(instructions.snippet.contains("\"theme\""))
        #expect(instructions.snippet == fileSystem.text(at: settingsURL))
    }

    // MARK: - Reading the fallback does not write

    /// The fallback exists precisely because writing is not permitted, so asking
    /// for it must not be a write in disguise.
    @Test("building the instructions touches nothing on disk")
    func instructionsDoNotWrite() throws {
        let fileSystem = InMemoryManualSetupFileSystem()
        let installer = ClaudeCodeHookInstaller(
            homeDirectory: Self.homeDirectory,
            fileSystem: fileSystem
        )

        _ = try installer.manualSetupInstructions()

        #expect(fileSystem.writeCount == 0)
        #expect(fileSystem.createdDirectories.isEmpty)
    }

    // MARK: - The instructions around the snippet

    @Test("names the destination file in the steps")
    func stepsNameTheDestination() {
        let instructions = ManualSetupInstructions(
            agent: .codex,
            destinationPath: "/Users/tester/.codex/config.toml",
            snippet: "notify = []\n"
        )

        #expect(instructions.steps.contains { $0.contains("/Users/tester/.codex/config.toml") })
        #expect(instructions.summary.contains("/Users/tester/.codex/config.toml"))
        #expect(instructions.title == "Set up Codex by hand")
    }

    @Test("keeps the snippet out of the step text")
    func stepsDoNotParaphraseTheSnippet() {
        let snippet = "notify = [\"/Applications/NotchFlow\"]\n"
        let instructions = ManualSetupInstructions(
            agent: .codex,
            destinationPath: "/Users/tester/.codex/config.toml",
            snippet: snippet
        )

        #expect(instructions.steps.allSatisfy { !$0.contains(snippet) })
    }
}

private final class InMemoryManualSetupFileSystem: ClaudeCodeHookFileSystem,
    CodexHookFileSystem,
    OpenCodePluginFileSystem,
    @unchecked Sendable
{
    private var files: [URL: Data]
    private(set) var createdDirectories: [URL] = []
    private(set) var writeCount = 0

    init(files: [URL: Data] = [:]) {
        self.files = files
    }

    func readFile(at url: URL) throws -> Data? {
        files[url]
    }

    func createDirectory(at url: URL) throws {
        createdDirectories.append(url)
    }

    func writeFileAtomically(_ data: Data, to url: URL) throws {
        files[url] = data
        writeCount += 1
    }

    func removeFile(at url: URL) throws {
        files.removeValue(forKey: url)
    }

    func removeDirectoryIfEmpty(at url: URL) throws {}

    func text(at url: URL) -> String? {
        files[url].map { String(decoding: $0, as: UTF8.self) }
    }
}
