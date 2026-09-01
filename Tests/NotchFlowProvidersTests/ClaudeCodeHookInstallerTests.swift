import Foundation
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
        #expect(try hookCommands(in: proposal).count == 1)
        #expect(try hookCommands(in: proposal).first?.hasSuffix(" &") == true)
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

        #expect(throws: ClaudeCodeHookInstallerError.configurationChangedSinceInstall) {
            try installer.uninstall()
        }
        #expect(fileSystem.text(at: Self.settingsURL) == changed)
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
