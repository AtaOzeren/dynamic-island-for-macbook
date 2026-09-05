import Foundation
import Testing

@testable import NotchFlowProviders

@Suite("OpenCodePluginInstaller")
struct OpenCodePluginInstallerTests {
    private static let homeDirectory = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    private static let pluginURL = homeDirectory.appending(
        path: ".config/opencode/plugins/notchflow.ts"
    )
    private static let backupURL = homeDirectory.appending(
        path: ".config/opencode/plugins/notchflow.ts.notchflow-backup"
    )
    private static let pluginsDirectory = pluginURL.deletingLastPathComponent()

    @Test("fresh install creates the plugin tree and generated plugin")
    func freshInstall() throws {
        let fileSystem = InMemoryOpenCodePluginFileSystem()
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        let proposal = try installer.proposedPlugin()
        try installer.install()

        #expect(fileSystem.createdDirectories == [Self.pluginsDirectory])
        #expect(fileSystem.text(at: Self.pluginURL) == proposal)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
        #expect(proposal.contains("export const NotchFlowPlugin: Plugin"))
        #expect(proposal.contains(#"fetch(`http://127.0.0.1:${port}/ai-status`"#))
    }

    @Test("install and uninstall preserve unrelated plugin files")
    func unrelatedFilesSurvive() throws {
        let unrelatedURL = Self.pluginsDirectory.appending(path: "user-plugin.ts")
        let unrelated = Data("export const UserPlugin = async () => ({})\n".utf8)
        let fileSystem = InMemoryOpenCodePluginFileSystem(files: [unrelatedURL: unrelated])
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        try installer.uninstall()

        #expect(fileSystem.data(at: unrelatedURL) == unrelated)
        #expect(fileSystem.data(at: Self.pluginURL) == nil)
        #expect(fileSystem.directories.contains(Self.pluginsDirectory))
    }

    @Test("reinstall is idempotent and byte-identical")
    func reinstallIsIdempotent() throws {
        let fileSystem = InMemoryOpenCodePluginFileSystem()
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        let firstInstall = try #require(fileSystem.data(at: Self.pluginURL))
        let writesAfterFirstInstall = fileSystem.writeCount
        try installer.install()

        #expect(fileSystem.data(at: Self.pluginURL) == firstInstall)
        #expect(fileSystem.writeCount == writesAfterFirstInstall)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
    }

    @Test("uninstall removes a fresh plugin and empty parent directories")
    func uninstallFreshInstallRemovesEmptyParents() throws {
        let fileSystem = InMemoryOpenCodePluginFileSystem()
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        try installer.uninstall()

        #expect(fileSystem.data(at: Self.pluginURL) == nil)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
        #expect(!fileSystem.directories.contains(Self.pluginsDirectory))
        #expect(!fileSystem.directories.contains(Self.pluginsDirectory.deletingLastPathComponent()))
    }

    @Test("failed plugin write leaves no partial file")
    func failedWriteLeavesNoPartialFile() throws {
        let fileSystem = InMemoryOpenCodePluginFileSystem()
        fileSystem.failWriteURL = Self.pluginURL
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        #expect(throws: TestFileSystemError.writeFailed) {
            try installer.install()
        }

        #expect(fileSystem.data(at: Self.pluginURL) == nil)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
    }

    @Test("modified NotchFlow file is backed up before overwrite and restored")
    func modifiedPluginIsBackedUpAndRestored() throws {
        let modified = Data("export const MyNotchFlowPlugin = true\n".utf8)
        let fileSystem = InMemoryOpenCodePluginFileSystem(files: [Self.pluginURL: modified])
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()

        #expect(fileSystem.data(at: Self.backupURL) == modified)
        #expect(fileSystem.data(at: Self.pluginURL) != modified)

        try installer.uninstall()

        #expect(fileSystem.data(at: Self.pluginURL) == modified)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
    }

    @Test("uninstall never overwrites a plugin changed after installation")
    func uninstallPreservesLaterChanges() throws {
        let original = Data("export const MyNotchFlowPlugin = true\n".utf8)
        let fileSystem = InMemoryOpenCodePluginFileSystem(files: [Self.pluginURL: original])
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        let changed = try #require(fileSystem.data(at: Self.pluginURL)) + Data("// user change\n".utf8)
        fileSystem.setData(changed, at: Self.pluginURL)

        try installer.uninstall()

        #expect(fileSystem.data(at: Self.pluginURL) == changed)
        #expect(fileSystem.data(at: Self.backupURL) == original)
    }

    @Test("install replaces and uninstall removes a v3-era plugin")
    func installAndUninstallLegacyPlugin() throws {
        let legacy = Data(
            """
            import type { Plugin } from "@opencode-ai/plugin"
            import { spawn } from "node:child_process"
            export const NotchFlowPlugin: Plugin = async () => ({
              "session.created": async () => ({ agentId: "opencode" }),
              "tool.execute.before": async () => spawn("open", ["-g", "notchflow://ai-status"]),
            })
            """.utf8
        )
        let fileSystem = InMemoryOpenCodePluginFileSystem(files: [Self.pluginURL: legacy])
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        #expect(installer.installationState() == .hookAbsent)
        try installer.install()
        #expect(fileSystem.data(at: Self.pluginURL) != legacy)

        try installer.uninstall()

        #expect(fileSystem.data(at: Self.pluginURL) == legacy)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
    }

    @Test("uninstall removes a v3-era plugin without a backup")
    func uninstallLegacyPluginWithoutBackup() throws {
        let legacy = Data(
            """
            import type { Plugin } from "@opencode-ai/plugin"
            import { spawn } from "node:child_process"
            export const NotchFlowPlugin: Plugin = async () => ({
              "session.created": async () => ({ agentId: "opencode" }),
              "tool.execute.before": async () => spawn("open", ["-g", "notchflow://ai-status"]),
            })
            """.utf8
        )
        let fileSystem = InMemoryOpenCodePluginFileSystem(files: [Self.pluginURL: legacy])

        try Self.makeInstaller(fileSystem: fileSystem).uninstall()

        #expect(fileSystem.data(at: Self.pluginURL) == nil)
    }

    @Test("installation state is missing when no plugin file exists")
    func installationStateWithoutPluginFile() {
        let fileSystem = InMemoryOpenCodePluginFileSystem()

        #expect(Self.makeInstaller(fileSystem: fileSystem).installationState() == .configurationMissing)
        #expect(fileSystem.writeCount == 0)
        #expect(fileSystem.createdDirectories.isEmpty)
    }

    @Test("installation state is absent when the plugin file is not ours")
    func installationStateWithForeignPlugin() {
        let fileSystem = InMemoryOpenCodePluginFileSystem(
            files: [Self.pluginURL: Data("export const Something = async () => ({})\n".utf8)]
        )

        #expect(Self.makeInstaller(fileSystem: fileSystem).installationState() == .hookAbsent)
        #expect(fileSystem.writeCount == 0)
    }

    @Test("installation state is installed after install writes the plugin")
    func installationStateAfterInstall() throws {
        let fileSystem = InMemoryOpenCodePluginFileSystem()
        let installer = Self.makeInstaller(fileSystem: fileSystem)
        try installer.install()

        let writesAfterInstall = fileSystem.writeCount

        #expect(installer.installationState() == .hookInstalled)
        #expect(fileSystem.writeCount == writesAfterInstall)
    }

    @Test("installation state is unreadable when the plugin file cannot be read")
    func installationStateWithUnreadablePlugin() {
        let fileSystem = InMemoryOpenCodePluginFileSystem(
            files: [Self.pluginURL: Data("export const NotchFlowPlugin = 1\n".utf8)]
        )
        fileSystem.failReadURL = Self.pluginURL

        #expect(
            Self.makeInstaller(fileSystem: fileSystem).installationState() == .configurationUnreadable
        )
        #expect(fileSystem.writeCount == 0)
    }

    private static func makeInstaller(
        fileSystem: InMemoryOpenCodePluginFileSystem
    ) -> OpenCodePluginInstaller {
        OpenCodePluginInstaller(
            homeDirectory: homeDirectory,
            fileSystem: fileSystem
        )
    }
}

private enum TestFileSystemError: Error {
    case writeFailed
    case readFailed
}

private final class InMemoryOpenCodePluginFileSystem: OpenCodePluginFileSystem,
    @unchecked Sendable
{
    private(set) var files: [URL: Data]
    private(set) var directories: Set<URL>
    private(set) var createdDirectories: [URL] = []
    private(set) var writeCount = 0
    var failWriteURL: URL?
    var failReadURL: URL?

    init(files: [URL: Data] = [:]) {
        self.files = files
        directories = Set(files.keys.map { $0.deletingLastPathComponent() })
    }

    func readFile(at url: URL) throws -> Data? {
        guard failReadURL != url else {
            throw TestFileSystemError.readFailed
        }
        return files[url]
    }

    func createDirectory(at url: URL) throws {
        createdDirectories.append(url)
        directories.insert(url)
    }

    func writeFileAtomically(_ data: Data, to url: URL) throws {
        guard failWriteURL != url else {
            throw TestFileSystemError.writeFailed
        }
        files[url] = data
        directories.insert(url.deletingLastPathComponent())
        writeCount += 1
    }

    func removeFile(at url: URL) throws {
        files.removeValue(forKey: url)
    }

    func removeDirectoryIfEmpty(at url: URL) throws {
        let hasFiles = files.keys.contains { $0.deletingLastPathComponent() == url }
        let hasDirectories = directories.contains { $0 != url && $0.deletingLastPathComponent() == url }
        if !hasFiles, !hasDirectories {
            directories.remove(url)
        }
    }

    func data(at url: URL) -> Data? {
        files[url]
    }

    func text(at url: URL) -> String? {
        files[url].flatMap { String(bytes: $0, encoding: .utf8) }
    }

    func setData(_ data: Data, at url: URL) {
        files[url] = data
    }
}
