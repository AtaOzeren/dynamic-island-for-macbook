import Foundation
import NotchFlowCore
import Testing

@testable import NotchFlowProviders

@Suite("ClaudeCodeHookInstaller")
struct ClaudeCodeHookInstallerTests {
    private static let homeDirectory = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    private static let settingsURL = homeDirectory.appending(path: ".claude/settings.json")
    private static let backupURL = homeDirectory.appending(
        path: ".claude/settings.json.notchflow-backup"
    )

    @Test("fresh install creates the settings directory and async hook")
    func freshInstall() throws {
        let fileSystem = InMemoryClaudeCodeFileSystem()
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        let proposal = try installer.proposedSettings()
        try installer.install()

        #expect(fileSystem.createdDirectories == [Self.settingsURL.deletingLastPathComponent()])
        let installed = try #require(fileSystem.text(at: Self.settingsURL))
        #expect(
            try jsonObject(from: Data(installed.utf8)) as NSDictionary == jsonObject(from: Data(proposal.utf8))
                as NSDictionary)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
        #expect(try allHookCommands(in: proposal).count == 9)
        #expect(try allHookCommands(in: proposal).allSatisfy { $0.hasSuffix(" &") })
        let hooks = try #require(jsonObject(from: Data(proposal.utf8))["hooks"] as? [String: Any])
        #expect(hooks["SubagentStart"] != nil)
        #expect(hooks["SubagentStop"] != nil)
    }

    @Test("install merges settings and backs up the original bytes")
    func mergePreservesExistingSettings() throws {
        let original = Data(
            #"{"permissions":{"allow":["Bash(git status)"]},"hooks":{"Stop":[{"hooks":[]}]}}"#.utf8
        )
        let fileSystem = InMemoryClaudeCodeFileSystem(files: [Self.settingsURL: original])

        try Self.makeInstaller(fileSystem: fileSystem).install()

        let installed = try #require(fileSystem.data(at: Self.settingsURL))
        let root = try jsonObject(from: installed)
        let permissions = try #require(root["permissions"] as? [String: Any])
        let hooks = try #require(root["hooks"] as? [String: Any])

        #expect(permissions["allow"] as? [String] == ["Bash(git status)"])
        #expect((hooks["Stop"] as? [Any])?.count == 2)
        #expect(fileSystem.data(at: Self.backupURL) == original)
        #expect(try hookCommands(in: String(decoding: installed, as: UTF8.self)).count == 1)
    }

    @Test("reinstall keeps one hook and does not rewrite files")
    func reinstallIsIdempotent() throws {
        let original = Data(#"{"theme":"dark"}"#.utf8)
        let fileSystem = InMemoryClaudeCodeFileSystem(files: [Self.settingsURL: original])
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        let writesAfterFirstInstall = fileSystem.writeCount
        try installer.install()

        let installed = try #require(fileSystem.text(at: Self.settingsURL))
        #expect(try hookCommands(in: installed).count == 1)
        #expect(fileSystem.data(at: Self.backupURL) == original)
        #expect(fileSystem.writeCount == writesAfterFirstInstall)
    }

    @Test("uninstall restores the original bytes and is idempotent")
    func uninstallRestoresBackup() throws {
        let original = Data("{\n  \"theme\": \"dark\"\n}\n".utf8)
        let fileSystem = InMemoryClaudeCodeFileSystem(files: [Self.settingsURL: original])
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        try installer.uninstall()
        let writesAfterFirstUninstall = fileSystem.writeCount
        try installer.uninstall()

        #expect(fileSystem.data(at: Self.settingsURL) == original)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
        #expect(fileSystem.writeCount == writesAfterFirstUninstall)
    }

    @Test("uninstall never overwrites settings changed after installation")
    func uninstallPreservesLaterChanges() throws {
        let original = Data(#"{"theme":"dark"}"#.utf8)
        let fileSystem = InMemoryClaudeCodeFileSystem(files: [Self.settingsURL: original])
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        let changed = try #require(fileSystem.text(at: Self.settingsURL))
            .replacingOccurrences(of: "\"dark\"", with: "\"light\"")
        fileSystem.setText(changed, at: Self.settingsURL)

        try installer.uninstall()

        let remaining = try #require(fileSystem.text(at: Self.settingsURL))
        #expect(remaining.contains("\"light\""))
        #expect(!remaining.contains(HookSnippetGenerator.managedHookMarker))
        #expect(fileSystem.data(at: Self.backupURL) == original)
    }

    /// The launch-time sweep uninstalls a disabled agent's hook, and after an
    /// upgrade that hook carries an earlier marker while the backup from the
    /// original install is still on disk. That must strip the hook, not fail on
    /// every launch.
    @Test("uninstall strips a previous version's hook when the backup no longer matches")
    func uninstallStripsLegacyHookBesideBackup() throws {
        let original = Data(#"{"theme":"dark"}"#.utf8)
        let legacyCommand = #"python3 -c 'print(1)' # notchflow_hook_v3"#
        let legacySettings = try JSONSerialization.data(withJSONObject: [
            "theme": "dark",
            "hooks": ["Stop": [["hooks": [["type": "command", "command": legacyCommand]]]]],
        ])
        let fileSystem = InMemoryClaudeCodeFileSystem(files: [
            Self.settingsURL: legacySettings,
            Self.backupURL: original,
        ])

        try Self.makeInstaller(fileSystem: fileSystem).uninstall()

        let remaining = try #require(fileSystem.text(at: Self.settingsURL))
        #expect(remaining.contains("\"dark\""))
        #expect(!remaining.contains("notchflow_hook_v3"))
        #expect(fileSystem.data(at: Self.backupURL) == original)
    }

    @Test("uninstall removes a fresh settings file")
    func uninstallFreshInstall() throws {
        let fileSystem = InMemoryClaudeCodeFileSystem()
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        try installer.uninstall()
        try installer.uninstall()

        #expect(fileSystem.data(at: Self.settingsURL) == nil)
    }

    @Test("invalid existing JSON aborts before any filesystem mutation")
    func invalidExistingJSON() throws {
        let invalidSettings = Data(#"{"hooks": "#.utf8)
        let fileSystem = InMemoryClaudeCodeFileSystem(
            files: [Self.settingsURL: invalidSettings]
        )
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        #expect(throws: ClaudeCodeHookInstallerError.invalidExistingSettings) {
            try installer.install()
        }
        #expect(fileSystem.data(at: Self.settingsURL) == invalidSettings)
        #expect(fileSystem.createdDirectories.isEmpty)
        #expect(fileSystem.writeCount == 0)
    }

    @Test("atomic write failure leaves the settings file unchanged")
    func atomicWriteFailure() throws {
        let original = Data(#"{"theme":"dark"}"#.utf8)
        let fileSystem = InMemoryClaudeCodeFileSystem(
            files: [Self.settingsURL: original],
            failingWriteURL: Self.settingsURL
        )

        #expect(throws: InMemoryClaudeCodeFileSystem.Failure.writeFailed) {
            try Self.makeInstaller(fileSystem: fileSystem).install()
        }
        #expect(fileSystem.data(at: Self.settingsURL) == original)
        #expect(fileSystem.data(at: Self.backupURL) == original)
    }

    /// A backup that no longer parses must stop the restore before the
    /// settings file is touched — silently skipping past it would leave the
    /// managed hook installed with no way back to the user's bytes.
    @Test("uninstall aborts on a corrupt backup without touching settings")
    func uninstallWithCorruptBackupAborts() throws {
        let corruptBackup = Data(#"{"hooks": "#.utf8)
        let fileSystem = InMemoryClaudeCodeFileSystem(files: [Self.backupURL: corruptBackup])

        #expect(throws: ClaudeCodeHookInstallerError.invalidExistingSettings) {
            try Self.makeInstaller(fileSystem: fileSystem).uninstall()
        }
        #expect(fileSystem.data(at: Self.backupURL) == corruptBackup)
        #expect(fileSystem.data(at: Self.settingsURL) == nil)
        #expect(fileSystem.writeCount == 0)
    }

    @Test("installation state is missing when no settings file exists")
    func installationStateWithoutSettingsFile() {
        let fileSystem = InMemoryClaudeCodeFileSystem()

        #expect(Self.makeInstaller(fileSystem: fileSystem).installationState() == .configurationMissing)
        #expect(fileSystem.writeCount == 0)
        #expect(fileSystem.createdDirectories.isEmpty)
    }

    @Test("installation state is absent when settings exist without our hook")
    func installationStateWithForeignSettings() {
        let fileSystem = InMemoryClaudeCodeFileSystem(
            files: [Self.settingsURL: Data(#"{"permissions":{"allow":["Bash(git status)"]}}"#.utf8)]
        )

        #expect(Self.makeInstaller(fileSystem: fileSystem).installationState() == .hookAbsent)
        #expect(fileSystem.writeCount == 0)
    }

    @Test("installation state is installed after install writes the hook")
    func installationStateAfterInstall() throws {
        let fileSystem = InMemoryClaudeCodeFileSystem()
        let installer = Self.makeInstaller(fileSystem: fileSystem)
        try installer.install()

        let writesAfterInstall = fileSystem.writeCount

        #expect(installer.installationState() == .hookInstalled)
        #expect(fileSystem.writeCount == writesAfterInstall)
    }

    @Test("installation state is unreadable when the settings file is corrupt")
    func installationStateWithCorruptSettings() {
        let corrupt = Data("{ this is not json".utf8)
        let fileSystem = InMemoryClaudeCodeFileSystem(files: [Self.settingsURL: corrupt])

        #expect(
            Self.makeInstaller(fileSystem: fileSystem).installationState() == .configurationUnreadable
        )
        #expect(fileSystem.data(at: Self.settingsURL) == corrupt)
        #expect(fileSystem.writeCount == 0)
    }

    private static func makeInstaller(
        fileSystem: InMemoryClaudeCodeFileSystem
    ) -> ClaudeCodeHookInstaller {
        ClaudeCodeHookInstaller(
            homeDirectory: homeDirectory,
            fileSystem: fileSystem
        )
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func hookCommands(in settings: String) throws -> [String] {
        let root = try jsonObject(from: Data(settings.utf8))
        let hooks = try #require(root["hooks"] as? [String: Any])
        let eventHooks = try #require(hooks["PreToolUse"] as? [[String: Any]])
        return eventHooks.flatMap { group in
            (group["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
        }
    }

    private func allHookCommands(in settings: String) throws -> [String] {
        let root = try jsonObject(from: Data(settings.utf8))
        let hooks = try #require(root["hooks"] as? [String: Any])
        return hooks.values.flatMap { event in
            (event as? [[String: Any]])?.flatMap { group in
                (group["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
            } ?? []
        }
    }

    // MARK: - Upgrading from an earlier NotchFlow

    /// The upgrade path. Installing over a previous version's hook must replace
    /// it, not sit beside it: appending alone left the older, broken command
    /// firing on the same event, so every message was delivered twice and the
    /// defect the new version fixes survived the update.
    @Test("install replaces a hook an earlier version wrote")
    func installReplacesPreviousVersionHook() throws {
        let stale = """
            {
              "hooks" : {
                "Stop" : [
                  {
                    "hooks" : [
                      {
                        "type" : "command",
                        "command" : "URL=$(python3 -c 'uuid.uuid5(NS, x); print(1)' $EVENT); open -g notchflow://ai-status"
                      }
                    ]
                  }
                ]
              }
            }
            """
        let fileSystem = InMemoryClaudeCodeFileSystem(
            files: [Self.settingsURL: Data(stale.utf8)]
        )

        try Self.makeInstaller(fileSystem: fileSystem).install()

        let installed = try #require(fileSystem.text(at: Self.settingsURL))
        #expect(!installed.contains("print(1)"))
        #expect(installed.contains(HookSnippetGenerator.managedHookMarker))
    }

    @Test("install replaces v2 hooks across old events when adding subagent events")
    func replacesV2HooksForSubagentUpgrade() throws {
        let oldCommand = #"python3 -c 'print(1)' # notchflow_hook_v2"#
        let oldGroup: [[String: Any]] = [
            [
                "hooks": [["type": "command", "command": oldCommand]]
            ]
        ]
        let oldHooks = Dictionary(
            uniqueKeysWithValues: [
                "UserPromptSubmit",
                "PreToolUse",
                "PostToolUse",
                "Notification",
                "Stop",
                "SessionEnd",
            ].map { ($0, oldGroup) }
        )
        let oldSettings = try JSONSerialization.data(withJSONObject: ["hooks": oldHooks])
        let fileSystem = InMemoryClaudeCodeFileSystem(files: [Self.settingsURL: oldSettings])

        try Self.makeInstaller(fileSystem: fileSystem).install()

        let installed = try #require(fileSystem.text(at: Self.settingsURL))
        let commands = try allHookCommands(in: installed)
        #expect(commands.count == 9)
        #expect(commands.allSatisfy { $0.contains(HookSnippetGenerator.managedHookMarker) })
        #expect(!installed.contains(oldCommand))
    }

    @Test("install replaces v3 hooks with loopback-only hooks")
    func replacesV3Hooks() throws {
        let oldCommand = #"python3 -c 'print(1)' # notchflow_hook_v3"#
        let oldSettings = try JSONSerialization.data(withJSONObject: [
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": oldCommand]]]]
            ]
        ])
        let fileSystem = InMemoryClaudeCodeFileSystem(files: [Self.settingsURL: oldSettings])

        try Self.makeInstaller(fileSystem: fileSystem).install()

        let installed = try #require(fileSystem.text(at: Self.settingsURL))
        #expect(installed.contains(HookSnippetGenerator.managedHookMarker))
        #expect(!installed.contains("notchflow_hook_v3"))
    }

    /// `StopFailure` is not an event Claude Code emits; an earlier version
    /// subscribed to it anyway. Nothing else would ever clear a hook under a
    /// name the generator no longer produces.
    @Test("install clears hooks under events this version no longer generates")
    func installClearsRetiredEvents() throws {
        let stale = """
            {
              "hooks" : {
                "PreCompact" : [
                  {
                    "hooks" : [
                      {
                        "type" : "command",
                        "command" : "python3 -c 'uuid.uuid5(NS, x)'; open -g notchflow://ai-status?payload=x"
                      }
                    ]
                  }
                ]
              }
            }
            """
        let fileSystem = InMemoryClaudeCodeFileSystem(
            files: [Self.settingsURL: Data(stale.utf8)]
        )

        try Self.makeInstaller(fileSystem: fileSystem).install()

        let installed = try #require(fileSystem.text(at: Self.settingsURL))
        #expect(!installed.contains("PreCompact"))
    }

    /// A hand-written hook that happens to open a `notchflow://` URL is the
    /// user's, not ours. Claiming it on the URL alone would delete their work
    /// on upgrade.
    @Test("install leaves a hand-written notchflow hook alone")
    func installPreservesHandWrittenNotchflowHooks() throws {
        let handWritten = """
            {
              "hooks" : {
                "Stop" : [
                  {
                    "hooks" : [
                      {
                        "type" : "command",
                        "command" : "open -g notchflow://ai-status?payload=mine"
                      }
                    ]
                  }
                ]
              }
            }
            """
        let fileSystem = InMemoryClaudeCodeFileSystem(
            files: [Self.settingsURL: Data(handWritten.utf8)]
        )

        try Self.makeInstaller(fileSystem: fileSystem).install()

        let installed = try #require(fileSystem.text(at: Self.settingsURL))
        #expect(installed.contains("payload=mine"))
        #expect(installed.contains(HookSnippetGenerator.managedHookMarker))
    }

    /// A hook the user wrote themselves is not ours to touch, however much it
    /// sits on an event we also use.
    @Test("install leaves a foreign hook on a shared event alone")
    func installPreservesForeignHooks() throws {
        let existing = """
            {
              "hooks" : {
                "Stop" : [
                  {
                    "hooks" : [
                      {
                        "type" : "command",
                        "command" : "say done"
                      }
                    ]
                  }
                ]
              }
            }
            """
        let fileSystem = InMemoryClaudeCodeFileSystem(
            files: [Self.settingsURL: Data(existing.utf8)]
        )

        try Self.makeInstaller(fileSystem: fileSystem).install()

        let installed = try #require(fileSystem.text(at: Self.settingsURL))
        #expect(installed.contains("say done"))
        #expect(installed.contains(HookSnippetGenerator.managedHookMarker))
    }

    /// The same protection as `installPreservesForeignHooks`, read from the
    /// other end: without a backup to restore, removal must take exactly the
    /// hook NotchFlow added and leave the user's own hook on the shared event
    /// working.
    @Test("uninstall without a backup keeps the user's hook on a shared event")
    func uninstallPreservesForeignHooks() throws {
        let existing = """
            {
              "hooks" : {
                "Stop" : [
                  {
                    "hooks" : [
                      {
                        "type" : "command",
                        "command" : "say done"
                      }
                    ]
                  }
                ]
              }
            }
            """
        let installed = InMemoryClaudeCodeFileSystem(
            files: [Self.settingsURL: Data(existing.utf8)]
        )
        try Self.makeInstaller(fileSystem: installed).install()
        let installedBytes = try #require(installed.data(at: Self.settingsURL))

        let withoutBackup = InMemoryClaudeCodeFileSystem(
            files: [Self.settingsURL: installedBytes]
        )
        try Self.makeInstaller(fileSystem: withoutBackup).uninstall()

        let remaining = try #require(withoutBackup.text(at: Self.settingsURL))
        #expect(remaining.contains("say done"))
        #expect(remaining.contains(HookSnippetGenerator.managedHookMarker) == false)
        let document = try #require(
            JSONSerialization.jsonObject(with: Data(remaining.utf8)) as? [String: Any]
        )
        let hooks = try #require(document["hooks"] as? [String: Any])
        #expect(hooks["Stop"] != nil, "the shared event keeps the user's hook group")
    }
}

private final class InMemoryClaudeCodeFileSystem: ClaudeCodeHookFileSystem, @unchecked Sendable {
    enum Failure: Error {
        case writeFailed
    }

    private var files: [URL: Data]
    private let failingWriteURL: URL?
    private(set) var createdDirectories: [URL] = []
    private(set) var writeCount = 0

    init(files: [URL: Data] = [:], failingWriteURL: URL? = nil) {
        self.files = files
        self.failingWriteURL = failingWriteURL
    }

    func readFile(at url: URL) throws -> Data? {
        files[url]
    }

    func createDirectory(at url: URL) throws {
        if !createdDirectories.contains(url) {
            createdDirectories.append(url)
        }
    }

    func writeFileAtomically(_ data: Data, to url: URL) throws {
        writeCount += 1
        if url == failingWriteURL {
            throw Failure.writeFailed
        }
        files[url] = data
    }

    func removeFile(at url: URL) throws {
        files[url] = nil
    }

    func data(at url: URL) -> Data? {
        files[url]
    }

    func text(at url: URL) -> String? {
        files[url].map { String(decoding: $0, as: UTF8.self) }
    }

    func setText(_ text: String, at url: URL) {
        files[url] = Data(text.utf8)
    }
}
