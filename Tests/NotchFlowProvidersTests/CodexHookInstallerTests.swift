import Foundation
import Testing

@testable import NotchFlowProviders

@Suite("CodexHookInstaller")
struct CodexHookInstallerTests {
    private static let homeDirectory = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    private static let configURL = homeDirectory.appending(path: ".codex/config.toml")
    private static let backupURL = homeDirectory.appending(
        path: ".codex/config.toml.notchflow-backup"
    )
    private static let notifierPath = "/Applications/NotchFlow.app/Contents/MacOS/notchflow-notify"

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
        #expect(installed.contains(Self.expectedNotifySetting))
        #expect(installed.contains("notify = \"leave-this-table-value\""))
        #expect(installed.contains("model = \"gpt-5\""))
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
            syntaxValidator: { !$0.contains("--agent") }
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

    private static var expectedNotifySetting: String {
        "notify = [\"\(notifierPath)\",\"--agent\",\"codex\"]"
    }

    private static func makeInstaller(
        fileSystem: InMemoryCodexHookFileSystem,
        syntaxValidator: @escaping CodexTOMLSyntaxValidator = { _ in true }
    ) -> CodexHookInstaller {
        CodexHookInstaller(
            homeDirectory: homeDirectory,
            notifierExecutablePath: notifierPath,
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
}
