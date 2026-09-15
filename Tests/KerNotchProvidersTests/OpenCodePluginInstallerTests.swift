import Foundation
import Testing

@testable import KerNotchProviders

@Suite("OpenCodePluginInstaller")
struct OpenCodePluginInstallerTests {
    private static let homeDirectory = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    private static let pluginURL = homeDirectory.appending(
        path: ".config/opencode/plugins/kernotch.ts"
    )
    private static let backupURL = homeDirectory.appending(
        path: ".config/opencode/plugins/kernotch.ts.kernotch-backup"
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
        #expect(proposal.contains("export const KerNotchPlugin: Plugin"))
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

    @Test("modified KerNotch file is backed up before overwrite and restored")
    func modifiedPluginIsBackedUpAndRestored() throws {
        let modified = Data("export const MyKerNotchPlugin = true\n".utf8)
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
        let original = Data("export const MyKerNotchPlugin = true\n".utf8)
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
            export const KerNotchPlugin: Plugin = async () => ({
              "session.created": async () => ({ agentId: "opencode" }),
              "tool.execute.before": async () => spawn("open", ["-g", "kernotch://ai-status"]),
            })
            """.utf8
        )
        let fileSystem = InMemoryOpenCodePluginFileSystem(files: [Self.pluginURL: legacy])
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        #expect(installer.installationState() == .hookAbsent)
        try installer.install()
        #expect(fileSystem.data(at: Self.pluginURL) != legacy)
        // An earlier generation is ours, not the user's: backing it up meant
        // uninstalling put back a plugin that launches the island through the
        // URL scheme on every event.
        #expect(fileSystem.data(at: Self.backupURL) == nil)

        try installer.uninstall()

        #expect(fileSystem.data(at: Self.pluginURL) == nil)
        #expect(fileSystem.data(at: Self.backupURL) == nil)
    }

    @Test("uninstall removes a v3-era plugin without a backup")
    func uninstallLegacyPluginWithoutBackup() throws {
        let legacy = Data(
            """
            import type { Plugin } from "@opencode-ai/plugin"
            import { spawn } from "node:child_process"
            export const KerNotchPlugin: Plugin = async () => ({
              "session.created": async () => ({ agentId: "opencode" }),
              "tool.execute.before": async () => spawn("open", ["-g", "kernotch://ai-status"]),
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
            files: [Self.pluginURL: Data("export const KerNotchPlugin = 1\n".utf8)]
        )
        fileSystem.failReadURL = Self.pluginURL

        #expect(
            Self.makeInstaller(fileSystem: fileSystem).installationState() == .configurationUnreadable
        )
        #expect(fileSystem.writeCount == 0)
    }

    // MARK: - Loopback-era generations

    /// The shape a machine updated from before the rename actually carries: the
    /// loopback plugin, posting to NotchFlow's port file, which no island
    /// publishes any more. The old recognition only knew the URL-scheme era, so
    /// installing left it in place, firing on every event and reaching nothing.
    @Test("install removes a pre-rename loopback plugin")
    func installRemovesPreRenameLoopbackPlugin() throws {
        let legacy = Self.loopbackGeneratedPlugin(exportName: "NotchFlowPlugin", discoveryDirectory: "NotchFlow")
        let fileSystem = InMemoryOpenCodePluginFileSystem(files: [Self.legacyPluginURL: legacy])
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()

        #expect(fileSystem.data(at: Self.legacyPluginURL) == nil)
        #expect(fileSystem.text(at: Self.pluginURL) == (try installer.proposedPlugin()))
        #expect(fileSystem.data(at: Self.backupURL) == nil)
    }

    /// Earlier versions backed up whatever sat at the path, so the pre-rename
    /// backup can itself hold an earlier generated plugin — one that opens the
    /// retired URL scheme on every event. Restoring it would bring that back.
    @Test("a generated plugin in the pre-rename backup is discarded, not restored")
    func generatedLegacyBackupIsNotRestored() throws {
        let legacy = Self.loopbackGeneratedPlugin(exportName: "NotchFlowPlugin", discoveryDirectory: "NotchFlow")
        let urlSchemeEra = Data(
            """
            import type { Plugin } from "@opencode-ai/plugin"
            import { spawn } from "node:child_process"
            export const NotchFlowPlugin: Plugin = async () => ({
              "session.created": async () => ({ agentId: "opencode" }),
              "tool.execute.before": async () => spawn("open", ["-g", "notchflow://ai-status"]),
            })
            """.utf8
        )
        let fileSystem = InMemoryOpenCodePluginFileSystem(
            files: [Self.legacyPluginURL: legacy, Self.legacyBackupURL: urlSchemeEra]
        )

        try Self.makeInstaller(fileSystem: fileSystem).install()

        #expect(fileSystem.data(at: Self.legacyPluginURL) == nil)
        #expect(fileSystem.data(at: Self.legacyBackupURL) == nil)
    }

    /// A leftover backup of an earlier generation must neither be restored over
    /// the plugin on uninstall nor stop a real user file from being backed up.
    @Test("a generated plugin left in a backup is discarded before install and uninstall")
    func generatedBackupIsDiscarded() throws {
        let earlier = Self.loopbackGeneratedPlugin(exportName: "KerNotchPlugin", discoveryDirectory: "KerNotch")
        let own = Data("export const MyPlugin = async () => ({})\n".utf8)
        let fileSystem = InMemoryOpenCodePluginFileSystem(
            files: [Self.pluginURL: own, Self.legacyBackupURL: earlier]
        )
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        #expect(fileSystem.data(at: Self.backupURL) == own)
        #expect(fileSystem.data(at: Self.legacyBackupURL) == nil)

        try installer.uninstall()
        #expect(fileSystem.data(at: Self.pluginURL) == own)
    }

    @Test("the user's own file in the pre-rename backup is still restored")
    func usersLegacyBackupIsRestored() throws {
        let legacy = Self.loopbackGeneratedPlugin(exportName: "NotchFlowPlugin", discoveryDirectory: "NotchFlow")
        let own = Data("export const MyPlugin = async () => ({})\n".utf8)
        let fileSystem = InMemoryOpenCodePluginFileSystem(
            files: [Self.legacyPluginURL: legacy, Self.legacyBackupURL: own]
        )

        try Self.makeInstaller(fileSystem: fileSystem).install()

        #expect(fileSystem.data(at: Self.legacyPluginURL) == own)
        #expect(fileSystem.data(at: Self.legacyBackupURL) == nil)
    }

    @Test("uninstall removes a pre-rename loopback plugin")
    func uninstallRemovesPreRenameLoopbackPlugin() throws {
        let legacy = Self.loopbackGeneratedPlugin(exportName: "NotchFlowPlugin", discoveryDirectory: "NotchFlow")
        let fileSystem = InMemoryOpenCodePluginFileSystem(files: [Self.legacyPluginURL: legacy])

        try Self.makeInstaller(fileSystem: fileSystem).uninstall()

        #expect(fileSystem.data(at: Self.legacyPluginURL) == nil)
    }

    @Test("install removes a leftover pre-rename plugin even when the current one is installed")
    func installRemovesLeftoverBesideCurrentPlugin() throws {
        let installer = Self.makeInstaller(fileSystem: InMemoryOpenCodePluginFileSystem())
        let current = Data(try installer.proposedPlugin().utf8)
        let legacy = Self.loopbackGeneratedPlugin(exportName: "NotchFlowPlugin", discoveryDirectory: "NotchFlow")
        let fileSystem = InMemoryOpenCodePluginFileSystem(
            files: [Self.pluginURL: current, Self.legacyPluginURL: legacy]
        )

        try Self.makeInstaller(fileSystem: fileSystem).install()

        #expect(fileSystem.data(at: Self.legacyPluginURL) == nil)
        #expect(fileSystem.data(at: Self.pluginURL) == current)
        #expect(fileSystem.writeCount == 0)
    }

    @Test("a plugin of the user's own under the pre-rename name is left alone")
    func userPluginUnderLegacyNameIsLeftAlone() throws {
        let own = Data("export const NotchFlowPlugin: Plugin = async () => ({})\n".utf8)
        let fileSystem = InMemoryOpenCodePluginFileSystem(files: [Self.legacyPluginURL: own])

        try Self.makeInstaller(fileSystem: fileSystem).install()

        #expect(fileSystem.data(at: Self.legacyPluginURL) == own)
    }

    /// An earlier generation of our own plugin is not the user's file. Backing
    /// it up meant uninstalling later restored the old plugin instead of
    /// removing it.
    @Test("install replaces an earlier loopback generation without backing it up")
    func installReplacesEarlierGenerationWithoutBackup() throws {
        let earlier = Self.loopbackGeneratedPlugin(exportName: "KerNotchPlugin", discoveryDirectory: "KerNotch")
        let fileSystem = InMemoryOpenCodePluginFileSystem(files: [Self.pluginURL: earlier])
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        #expect(fileSystem.data(at: Self.backupURL) == nil)

        try installer.uninstall()
        #expect(fileSystem.data(at: Self.pluginURL) == nil)
    }

    @Test("uninstall removes an earlier loopback generation left behind by an update")
    func uninstallRemovesEarlierGeneration() throws {
        let earlier = Self.loopbackGeneratedPlugin(exportName: "KerNotchPlugin", discoveryDirectory: "KerNotch")
        let fileSystem = InMemoryOpenCodePluginFileSystem(files: [Self.pluginURL: earlier])

        try Self.makeInstaller(fileSystem: fileSystem).uninstall()

        #expect(fileSystem.data(at: Self.pluginURL) == nil)
    }

    @Test("a hand-written plugin that posts to KerNotch is still backed up and restored")
    func handWrittenPluginPostingToKerNotchIsBackedUp() throws {
        let own = Data(
            """
            const PORT_FILE = join(homedir(), "Library", "Application Support", "KerNotch", "ipc-port")
            export const MyPlugin = async () => fetch(`http://127.0.0.1:${port}/ai-status`)
            """.utf8
        )
        let fileSystem = InMemoryOpenCodePluginFileSystem(files: [Self.pluginURL: own])
        let installer = Self.makeInstaller(fileSystem: fileSystem)

        try installer.install()
        #expect(fileSystem.data(at: Self.backupURL) == own)

        try installer.uninstall()
        #expect(fileSystem.data(at: Self.pluginURL) == own)
    }

    private static let legacyPluginURL = homeDirectory.appending(
        path: ".config/opencode/plugins/notchflow.ts"
    )
    private static let legacyBackupURL = homeDirectory.appending(
        path: ".config/opencode/plugins/notchflow.ts.notchflow-backup"
    )

    /// A minimal loopback-era plugin carrying every marker a generated one has.
    private static func loopbackGeneratedPlugin(exportName: String, discoveryDirectory: String) -> Data {
        Data(
            """
            import type { Plugin } from "@opencode-ai/plugin"
            const PORT_FILE = join(homedir(), "Library", "Application Support", "\(discoveryDirectory)", "ipc-port")
            const deliver = (port: string, body: string) =>
              fetch(`http://127.0.0.1:${port}/ai-status`, { method: "POST", body })
            export const \(exportName): Plugin = async () => ({
              event: async ({ event }) => {
                if (event.type === "session.created") deliver("1", JSON.stringify({ agentId: "opencode" }))
              },
              "tool.execute.before": async () => {},
            })
            """.utf8
        )
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
