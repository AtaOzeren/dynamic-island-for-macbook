import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowProviders

@Suite("CodexHookInstaller")
struct CodexHookInstallerTests {
    private static let homeDirectory = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    private static let configURL = homeDirectory.appending(path: ".codex/config.toml")
    private static let hooksURL = homeDirectory.appending(path: ".codex/hooks.json")
    private static let backupURL = homeDirectory.appending(
        path: ".codex/config.toml.notchflow-backup"
    )

    @Test("fresh install creates the config directory and notify setting")
    func freshInstall() throws {
        let fileSystem = InMemoryCodexHookFileSystem()
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        let proposal = try installer.proposedConfiguration()
        try installer.install()

        #expect(fileSystem.createdDirectories == [Self.configURL.deletingLastPathComponent()])
        #expect(fileSystem.text(at: Self.configURL) == proposal)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
        #expect(proposal.contains(Self.expectedNotifySetting))
        #expect(fileSystem.text(at: Self.hooksURL)?.contains("notchflow_codex_hook_v1=True") == true)
    }

    @Test("install preserves existing lifecycle hooks and adds one managed handler per event")
    func installMergesLifecycleHooks() throws {
        let existingHooks = Data(
            """
            {
              "description": "Keep user hooks",
              "hooks": {
                "SessionStart": [
                  {
                    "hooks": [
                      {
                        "type": "command",
                        "command": "python3 existing.py"
                      }
                    ]
                  }
                ]
              }
            }
            """.utf8
        )
        let fileSystem = InMemoryCodexHookFileSystem(
            files: [Self.hooksURL: existingHooks]
        )

        try Self.makeInstaller(fileSystem: fileSystem).install()

        let document = try #require(fileSystem.jsonObject(at: Self.hooksURL))
        #expect(document["description"] as? String == "Keep user hooks")
        let hooks = try #require(document["hooks"] as? [String: Any])
        #expect(hooks["SessionStart"] != nil)
        for event in Self.managedLifecycleEvents {
            #expect(Self.managedHandlerCount(for: event, in: hooks) == 1)
        }
    }

    @Test("install preserves unrelated TOML and backs up the original bytes")
    func mergePreservesExistingConfiguration() throws {
        let original = Data(
            """
            # Keep this account configuration.
            model = "gpt-5"

            [projects."/Users/tester/Work"]
            trust_level = "trusted"
            """.utf8
        )
        let fileSystem = InMemoryCodexHookFileSystem(files: [Self.configURL: original])

        try Self.makeInstaller(fileSystem: fileSystem).install()

        let installed = try #require(fileSystem.text(at: Self.configURL))
        #expect(installed.contains("# Keep this account configuration."))
        #expect(installed.contains("model = \"gpt-5\""))
        #expect(installed.contains("[projects.\"/Users/tester/Work\"]"))
        #expect(installed.contains("trust_level = \"trusted\""))
        #expect(installed.contains(Self.expectedNotifySetting))
        #expect(fileSystem.data(at: Self.backupURL) == original)
    }

    @Test("install replaces only the root notify setting")
    func installReplacesExistingNotifySetting() throws {
        let original = Data(
            """
            notify = ["existing-notifier"]
            model = "gpt-5"

            [profile.team]
            notify = "leave-this-table-value"
            """.utf8
        )
        let fileSystem = InMemoryCodexHookFileSystem(files: [Self.configURL: original])

        try Self.makeInstaller(fileSystem: fileSystem).install()

        let installed = try #require(fileSystem.text(at: Self.configURL))
        #expect(!installed.contains("notify = [\"existing-notifier\"]"))
        #expect(installed.contains("notchflow_codex_notify_v2=True"))
        #expect(installed.contains("existing-notifier"))
        #expect(installed.contains("notify = \"leave-this-table-value\""))
        #expect(installed.contains("model = \"gpt-5\""))
    }

    @Test("install replaces multiline notify and preserves its command chain")
    func installReplacesMultilineNotify() throws {
        let originalText = """
            model = "gpt-5.6-sol"
            notify = [
                "/Applications/Codex Computer Use.app/Contents/MacOS/Notifier",
                "turn-ended",
            ]
            service_tier = "default"

            [projects."/Users/tester/Work"]
            trust_level = "trusted"
            """
        let original = Data(originalText.utf8)
        let fileSystem = InMemoryCodexHookFileSystem(files: [Self.configURL: original])
        let installer = CodexHookInstaller(
            homeDirectory: Self.homeDirectory,
            fileSystem: fileSystem
        )

        try installer.install()
        let installed = try #require(fileSystem.text(at: Self.configURL))

        #expect(installer.installationState() == .hookInstalled)
        #expect(installed.contains("Codex Computer Use.app/Contents/MacOS/Notifier"))
        #expect(installed.contains("turn-ended"))
        #expect(installed.contains("service_tier = \"default\""))
        #expect(fileSystem.data(at: Self.backupURL) == original)

        try installer.uninstall()
        #expect(fileSystem.data(at: Self.configURL) == original)
    }

    @Test("install recognizes NotchFlow nested by another notifier")
    func installPreservesNotifierWrappingNotchFlow() throws {
        let managedArguments = try #require(
            JSONSerialization.jsonObject(
                with: Data(
                    HookSnippetGenerator()
                        .codexNotifyFragment()
                        .dropFirst("notify = ".count)
                        .utf8
                )
            ) as? [String]
        )
        let nestedData = try JSONSerialization.data(
            withJSONObject: managedArguments,
            options: [.withoutEscapingSlashes]
        )
        let outerArguments = [
            "/Applications/ComputerUse.app/Contents/MacOS/Notifier",
            "turn-ended",
            "--previous-notify",
            String(decoding: nestedData, as: UTF8.self),
        ]
        let outerData = try JSONSerialization.data(
            withJSONObject: outerArguments,
            options: [.withoutEscapingSlashes]
        )
        let original = Data("notify = \(String(decoding: outerData, as: UTF8.self))\n".utf8)
        let fileSystem = InMemoryCodexHookFileSystem(
            files: [Self.configURL: original]
        )
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()

        #expect(fileSystem.data(at: Self.configURL) == original)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
        #expect(installer.installationState() == .hookInstalled)
    }

    @Test("install inserts notify before the first TOML table")
    func installInsertsNotifyBeforeFirstTable() throws {
        let original = Data(
            """
            [projects."/Users/tester/Work"]
            trust_level = "trusted"
            """.utf8
        )
        let fileSystem = InMemoryCodexHookFileSystem(files: [Self.configURL: original])

        try Self.makeInstaller(fileSystem: fileSystem).install()

        let installed = try #require(fileSystem.text(at: Self.configURL))
        let notifyRange = try #require(installed.range(of: Self.expectedNotifySetting))
        let tableRange = try #require(installed.range(of: "[projects."))
        #expect(notifyRange.lowerBound < tableRange.lowerBound)
    }

    @Test("reinstall keeps one managed setting and does not rewrite files")
    func reinstallIsIdempotent() throws {
        let original = Data("model = \"gpt-5\"\n".utf8)
        let fileSystem = InMemoryCodexHookFileSystem(files: [Self.configURL: original])
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        let writesAfterFirstInstall = fileSystem.writeCount
        try installer.install()

        let installed = try #require(fileSystem.text(at: Self.configURL))
        #expect(installed.components(separatedBy: Self.expectedNotifySetting).count == 2)
        #expect(fileSystem.data(at: Self.backupURL) == original)
        #expect(fileSystem.writeCount == writesAfterFirstInstall)
    }

    @Test("uninstall restores the original bytes and is idempotent")
    func uninstallRestoresBackup() throws {
        let original = Data("# formatting matters\nmodel='gpt-5'\n".utf8)
        let fileSystem = InMemoryCodexHookFileSystem(files: [Self.configURL: original])
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        try installer.uninstall()
        let writesAfterFirstUninstall = fileSystem.writeCount
        try installer.uninstall()

        #expect(fileSystem.data(at: Self.configURL) == original)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
        #expect(fileSystem.writeCount == writesAfterFirstUninstall)
    }

    @Test("uninstall removes only managed lifecycle handlers")
    func uninstallPreservesForeignLifecycleHooks() throws {
        let existingHooks = Data(
            """
            {
              "hooks": {
                "UserPromptSubmit": [
                  {
                    "hooks": [
                      {
                        "type": "command",
                        "command": "python3 existing.py"
                      }
                    ]
                  }
                ]
              }
            }
            """.utf8
        )
        let fileSystem = InMemoryCodexHookFileSystem(
            files: [Self.hooksURL: existingHooks]
        )
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        try installer.uninstall()

        let document = try #require(fileSystem.jsonObject(at: Self.hooksURL))
        let hooks = try #require(document["hooks"] as? [String: Any])
        #expect(Self.managedHandlerCount(for: "UserPromptSubmit", in: hooks) == 0)
        let promptGroups = try #require(hooks["UserPromptSubmit"] as? [[String: Any]])
        let promptGroup = try #require(promptGroups.first)
        let promptHandlers = try #require(promptGroup["hooks"] as? [[String: Any]])
        #expect(promptHandlers.first?["command"] as? String == "python3 existing.py")
    }

    @Test("uninstall never overwrites configuration changed after installation")
    func uninstallPreservesLaterChanges() throws {
        let original = Data("model = \"gpt-5\"\n".utf8)
        let fileSystem = InMemoryCodexHookFileSystem(files: [Self.configURL: original])
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        let changed = try #require(fileSystem.text(at: Self.configURL))
            .replacingOccurrences(of: "gpt-5", with: "gpt-5.1")
        fileSystem.setText(changed, at: Self.configURL)

        #expect(throws: CodexHookInstallerError.configurationChangedSinceInstall) {
            try installer.uninstall()
        }
        #expect(fileSystem.text(at: Self.configURL) == changed)
        #expect(fileSystem.data(at: Self.backupURL) == original)
    }

    @Test("uninstall removes a fresh config file")
    func uninstallFreshInstall() throws {
        let fileSystem = InMemoryCodexHookFileSystem()
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        try installer.uninstall()

        #expect(fileSystem.data(at: Self.configURL) == nil)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
    }

    @Test("uninstall from a fresh install preserves settings added later")
    func uninstallFreshInstallPreservesLaterSettings() throws {
        let fileSystem = InMemoryCodexHookFileSystem()
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        fileSystem.setText(
            Self.expectedNotifySetting + "\nmodel = \"gpt-5\"\n",
            at: Self.configURL
        )
        try installer.uninstall()

        #expect(fileSystem.text(at: Self.configURL) == "model = \"gpt-5\"\n")
        #expect(fileSystem.data(at: Self.backupURL) == nil)
    }

    @Test("invalid existing TOML aborts without writing")
    func invalidExistingConfigurationDoesNotWrite() throws {
        let original = Data("broken = [\n".utf8)
        let fileSystem = InMemoryCodexHookFileSystem(files: [Self.configURL: original])
        let installer = Self.makeInstaller(
            fileSystem: fileSystem,
            syntaxValidator: { !$0.contains("broken = [") }
        )

        #expect(throws: CodexHookInstallerError.invalidExistingConfiguration) {
            try installer.install()
        }
        #expect(fileSystem.data(at: Self.configURL) == original)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
        #expect(fileSystem.writeCount == 0)
    }

    @Test("invalid generated TOML aborts without writing")
    func invalidGeneratedConfigurationDoesNotWrite() throws {
        let original = Data("model = \"gpt-5\"\n".utf8)
        let fileSystem = InMemoryCodexHookFileSystem(files: [Self.configURL: original])
        let installer = Self.makeInstaller(
            fileSystem: fileSystem,
            syntaxValidator: { !$0.contains("python3") }
        )

        #expect(throws: CodexHookInstallerError.invalidGeneratedConfiguration) {
            try installer.install()
        }
        #expect(fileSystem.data(at: Self.configURL) == original)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
        #expect(fileSystem.writeCount == 0)
    }

    @Test("atomic config write failure leaves the original unchanged")
    func atomicWriteFailureDoesNotDamageConfiguration() throws {
        let original = Data("model = \"gpt-5\"\n".utf8)
        let fileSystem = InMemoryCodexHookFileSystem(files: [Self.configURL: original])
        fileSystem.failingWriteURL = Self.configURL

        #expect(throws: InMemoryCodexHookFileSystem.Failure.write) {
            try Self.makeInstaller(fileSystem: fileSystem).install()
        }
        #expect(fileSystem.data(at: Self.configURL) == original)
    }

    @Test("installation state is missing when no config file exists")
    func installationStateWithoutConfigFile() {
        let fileSystem = InMemoryCodexHookFileSystem()

        #expect(Self.makeInstaller(fileSystem: fileSystem).installationState() == .configurationMissing)
        #expect(fileSystem.writeCount == 0)
        #expect(fileSystem.createdDirectories.isEmpty)
    }

    @Test("installation state is absent when config exists without our notify")
    func installationStateWithForeignConfiguration() {
        let fileSystem = InMemoryCodexHookFileSystem(
            files: [Self.configURL: Data("model = \"gpt-5\"\n".utf8)]
        )

        #expect(Self.makeInstaller(fileSystem: fileSystem).installationState() == .hookAbsent)
        #expect(fileSystem.writeCount == 0)
    }

    @Test("legacy notify without lifecycle hooks is reported absent")
    func installationStateRequiresLifecycleHooks() {
        let fileSystem = InMemoryCodexHookFileSystem(
            files: [Self.configURL: Data((Self.expectedNotifySetting + "\n").utf8)]
        )

        #expect(Self.makeInstaller(fileSystem: fileSystem).installationState() == .hookAbsent)
    }

    @Test("invalid hooks JSON aborts without writing")
    func invalidHooksDocumentDoesNotWrite() {
        let invalidHooks = Data("{\"hooks\": [".utf8)
        let fileSystem = InMemoryCodexHookFileSystem(
            files: [Self.hooksURL: invalidHooks]
        )

        #expect(throws: CodexHookInstallerError.invalidExistingConfiguration) {
            try Self.makeInstaller(fileSystem: fileSystem).install()
        }
        #expect(fileSystem.data(at: Self.hooksURL) == invalidHooks)
        #expect(fileSystem.writeCount == 0)
    }

    @Test("installation state is installed after install writes the notify setting")
    func installationStateAfterInstall() throws {
        let fileSystem = InMemoryCodexHookFileSystem()
        let installer = Self.makeInstaller(fileSystem: fileSystem)
        try installer.install()

        let writesAfterInstall = fileSystem.writeCount

        #expect(installer.installationState() == .hookInstalled)
        #expect(fileSystem.writeCount == writesAfterInstall)
    }

    @Test("installation state is unreadable when the config fails validation")
    func installationStateWithInvalidConfiguration() {
        let invalid = Data("notify = [unterminated\n".utf8)
        let fileSystem = InMemoryCodexHookFileSystem(files: [Self.configURL: invalid])
        let installer = Self.makeInstaller(
            fileSystem: fileSystem,
            syntaxValidator: { !$0.contains("unterminated") }
        )

        #expect(installer.installationState() == .configurationUnreadable)
        #expect(fileSystem.data(at: Self.configURL) == invalid)
        #expect(fileSystem.writeCount == 0)
    }

    private static var expectedNotifySetting: String {
        HookSnippetGenerator().codexNotifyFragment().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let managedLifecycleEvents = [
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PermissionRequest",
        "Stop",
    ]

    private static func managedHandlerCount(
        for event: String,
        in hooks: [String: Any]
    ) -> Int {
        guard let groups = hooks[event] as? [[String: Any]] else { return 0 }
        return groups.reduce(into: 0) { count, group in
            guard let handlers = group["hooks"] as? [[String: Any]] else { return }
            count += handlers.filter { handler in
                (handler["command"] as? String)?.contains("notchflow_codex_hook_v1=True") == true
            }.count
        }
    }

    private static func makeInstaller(
        fileSystem: InMemoryCodexHookFileSystem,
        syntaxValidator: @escaping CodexTOMLSyntaxValidator = { _ in true }
    ) -> CodexHookInstaller {
        CodexHookInstaller(
            homeDirectory: homeDirectory,
            fileSystem: fileSystem,
            syntaxValidator: syntaxValidator
        )
    }
}

private final class InMemoryCodexHookFileSystem: CodexHookFileSystem, @unchecked Sendable {
    enum Failure: Error {
        case write
    }

    private var files: [URL: Data]
    private(set) var createdDirectories: [URL] = []
    private(set) var writeCount = 0
    var failingWriteURL: URL?

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
        if failingWriteURL == url {
            throw Failure.write
        }
        files[url] = data
        writeCount += 1
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

    func jsonObject(at url: URL) -> [String: Any]? {
        guard let data = files[url] else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
