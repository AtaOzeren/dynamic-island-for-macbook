import Foundation
import KerNotchCore

public enum OpenCodePluginInstallerError: Error, Equatable, Sendable {
    case invalidGeneratedPlugin
}

public protocol OpenCodePluginFileSystem: Sendable {
    func readFile(at url: URL) throws -> Data?
    func createDirectory(at url: URL) throws
    func writeFileAtomically(_ data: Data, to url: URL) throws
    func removeFile(at url: URL) throws
    func removeDirectoryIfEmpty(at url: URL) throws
}

public struct FoundationOpenCodePluginFileSystem: OpenCodePluginFileSystem {
    public init() {}

    public func readFile(at url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    public func writeFileAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public func removeFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    public func removeDirectoryIfEmpty(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        )
        if contents.isEmpty {
            try FileManager.default.removeItem(at: url)
        }
    }
}

public struct OpenCodePluginInstaller: Sendable {
    private static let pluginPath = ".config/opencode/plugins/kernotch.ts"

    /// Where the plugin lived before the app was renamed. Read and removed,
    /// never written, so a pre-rename install does not stay behind firing
    /// beside the new one.
    private static let legacyPluginPath = ".config/opencode/plugins/notchflow.ts"
    private static let backupSuffix = ".kernotch-backup"
    private static let legacyBackupSuffix = ".notchflow-backup"
    private static let removableParentCount = 3
    private static let generatedExportNames = ["KerNotchPlugin", "NotchFlowPlugin"]
    private static let discoveryDirectoryNames = ["KerNotch", "NotchFlow"]

    private let fileSystem: any OpenCodePluginFileSystem
    private let pluginURL: URL
    private let backupURL: URL
    private let legacyPluginURL: URL
    private let legacyBackupURL: URL

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: any OpenCodePluginFileSystem = FoundationOpenCodePluginFileSystem()
    ) {
        self.fileSystem = fileSystem
        pluginURL = homeDirectory.appending(path: Self.pluginPath)
        backupURL = URL(fileURLWithPath: pluginURL.path + Self.backupSuffix)
        legacyPluginURL = homeDirectory.appending(path: Self.legacyPluginPath)
        legacyBackupURL = URL(fileURLWithPath: legacyPluginURL.path + Self.legacyBackupSuffix)
    }

    /// The backup to restore from, preferring this version's over one a
    /// pre-rename version left behind.
    private func existingBackup() throws -> (url: URL, data: Data)? {
        for url in [backupURL, legacyBackupURL] {
            if let data = try fileSystem.readFile(at: url) { return (url, data) }
        }
        return nil
    }

    public func proposedPlugin() throws -> String {
        try generatedPlugin().text
    }

    /// The manual-setup fallback's content, produced by the same call `install()`
    /// writes from so the two can never disagree.
    public func manualSetupInstructions() throws -> ManualSetupInstructions {
        ManualSetupInstructions(
            agent: .opencode,
            destinationPath: pluginURL.path,
            snippet: try proposedPlugin()
        )
    }

    /// Whether `~/.config/opencode/plugins/kernotch.ts` is already our plugin.
    ///
    /// The file is one KerNotch owns outright, so the same whole-file byte
    /// comparison `install()` gates on is the entire definition of "installed";
    /// a file present but differing is the user's own plugin under our name,
    /// which is `hookAbsent`, not a merge to attempt.
    ///
    /// Reads only; it never creates the directory, the backup, or the file.
    public func installationState() -> HookInstallationState {
        do {
            guard let existingData = try fileSystem.readFile(at: pluginURL) else {
                return .configurationMissing
            }
            return try existingData == generatedPlugin().data ? .hookInstalled : .hookAbsent
        } catch {
            // Covers both an unreadable file and a generator that failed its own
            // validation. Neither can honestly answer "installed", and the
            // conservative case is the one that stops the UI claiming it is.
            return .configurationUnreadable
        }
    }

    public func install() throws {
        try discardGeneratedBackups()
        let generated = try generatedPlugin()
        let existingData = try fileSystem.readFile(at: pluginURL)
        guard existingData != generated.data else {
            // Already current, but a pre-rename plugin can still sit beside it.
            try removeLegacyPlugin()
            return
        }

        try fileSystem.createDirectory(at: pluginURL.deletingLastPathComponent())
        if let existingData, isGeneratedPlugin(existingData) == false, try existingBackup() == nil {
            try fileSystem.writeFileAtomically(existingData, to: backupURL)
        }
        try fileSystem.writeFileAtomically(generated.data, to: pluginURL)
        try removeLegacyPlugin()
    }

    /// Backups exist to give the user's own file back.
    ///
    /// Earlier versions backed up whatever sat at the path, an earlier
    /// generation of the plugin included. Restoring one of those would put back
    /// a plugin that launches the island through the retired URL scheme on
    /// every event, and its mere presence stopped the user's real file from
    /// being backed up. They are discarded before anything decides whether to
    /// back up or restore.
    private func discardGeneratedBackups() throws {
        for url in [backupURL, legacyBackupURL] {
            guard let data = try fileSystem.readFile(at: url), isGeneratedPlugin(data) else { continue }
            try fileSystem.removeFile(at: url)
        }
    }

    /// Deletes a plugin a pre-rename version installed, so the two do not both
    /// fire. A file under the old name that is not ours is left untouched.
    private func removeLegacyPlugin() throws {
        guard let data = try fileSystem.readFile(at: legacyPluginURL), isGeneratedPlugin(data) else {
            return
        }
        if let backupData = try fileSystem.readFile(at: legacyBackupURL) {
            try fileSystem.writeFileAtomically(backupData, to: legacyPluginURL)
            try fileSystem.removeFile(at: legacyBackupURL)
            return
        }
        try fileSystem.removeFile(at: legacyPluginURL)
    }

    public func uninstall() throws {
        try discardGeneratedBackups()
        try removeLegacyPlugin()
        if let (restoredFrom, backupData) = try existingBackup() {
            guard let pluginData = try fileSystem.readFile(at: pluginURL),
                pluginData == (try generatedPlugin().data) || isLegacyManagedPlugin(pluginData)
            else {
                // The file under our name is no longer ours to remove, and the
                // backup is not ours to restore over it.
                return
            }
            try fileSystem.writeFileAtomically(backupData, to: pluginURL)
            try fileSystem.removeFile(at: restoredFrom)
            return
        }

        guard let pluginData = try fileSystem.readFile(at: pluginURL) else {
            return
        }
        // With no backup there is nothing of the user's to protect, so an
        // earlier generation of our own plugin is removed as well — otherwise
        // turning OpenCode off after an update would leave the old one firing.
        let generatedData = try generatedPlugin().data
        guard
            pluginData == generatedData
                || isLegacyManagedPlugin(pluginData)
                || isLoopbackGeneratedPlugin(pluginData)
        else {
            return
        }
        try fileSystem.removeFile(at: pluginURL)
        try removeEmptyParents()
    }

    private func generatedPlugin() throws -> (text: String, data: Data) {
        let text = HookSnippetGenerator().openCodePluginFile()
        guard text.contains("export const KerNotchPlugin: Plugin"),
            text.contains("agentId: \"opencode\""),
            text.contains("session.created"),
            text.contains("tool.execute.before"),
            let data = text.data(using: .utf8)
        else {
            throw OpenCodePluginInstallerError.invalidGeneratedPlugin
        }
        return (text, data)
    }

    // OpenCode has no version marker by design; structural markers plus the
    // retired transport distinguish legacy generated plugins during uninstall.
    private func isLegacyManagedPlugin(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8), carriesGeneratedStructure(text) else {
            return false
        }
        return
            (text.contains("\(HookSnippetGenerator.urlScheme)://ai-status")
            || text.contains("\(HookSnippetGenerator.legacyURLScheme)://ai-status"))
            && text.contains(#"spawn("open""#)
    }

    /// Whether KerNotch or NotchFlow generated this plugin, in any transport era.
    private func isGeneratedPlugin(_ data: Data) -> Bool {
        isLegacyManagedPlugin(data) || isLoopbackGeneratedPlugin(data)
    }

    /// Whether this is a generated plugin from the loopback era, the current
    /// generation's predecessors included.
    ///
    /// Recognised by structure plus transport, never by file name: the plugin
    /// reads the island's port file and posts to its loopback route, which a
    /// plugin someone wrote for themselves has no reason to do in exactly this
    /// form. The pre-rename spelling posts to NotchFlow's port file, which no
    /// running island publishes any more — so left in place, it fires on every
    /// event and reaches nothing.
    private func isLoopbackGeneratedPlugin(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8), carriesGeneratedStructure(text) else {
            return false
        }
        let readsDiscoveryFile = Self.discoveryDirectoryNames.contains { directory in
            text.contains(#""Application Support", "\#(directory)", "ipc-port""#)
        }
        return readsDiscoveryFile && text.contains("fetch(`http://127.0.0.1:${port}/ai-status`")
    }

    /// The shape every generated plugin has carried, whichever transport it
    /// used. Export name and scheme both changed with the rename, so each is
    /// matched against this version's spelling or the pre-rename one.
    private func carriesGeneratedStructure(_ text: String) -> Bool {
        Self.generatedExportNames.contains { text.contains("export const \($0): Plugin") }
            && text.contains("agentId: \"opencode\"")
            && text.contains("session.created")
            && text.contains("tool.execute.before")
    }

    private func removeEmptyParents() throws {
        var parentURL = pluginURL.deletingLastPathComponent()
        for _ in 0..<Self.removableParentCount {
            try fileSystem.removeDirectoryIfEmpty(at: parentURL)
            parentURL.deleteLastPathComponent()
        }
    }
}
