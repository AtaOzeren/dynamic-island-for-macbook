import Foundation
import NotchFlowCore

public enum OpenCodePluginInstallerError: Error, Equatable, Sendable {
    case invalidGeneratedPlugin
    case pluginChangedSinceInstall
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
    private static let pluginPath = ".config/opencode/plugins/notchflow.ts"
    private static let backupSuffix = ".notchflow-backup"
    private static let removableParentCount = 3

    private let fileSystem: any OpenCodePluginFileSystem
    private let pluginURL: URL
    private let backupURL: URL

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: any OpenCodePluginFileSystem = FoundationOpenCodePluginFileSystem()
    ) {
        self.fileSystem = fileSystem
        pluginURL = homeDirectory.appending(path: Self.pluginPath)
        backupURL = URL(fileURLWithPath: pluginURL.path + Self.backupSuffix)
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

    /// Whether `~/.config/opencode/plugins/notchflow.ts` is already our plugin.
    ///
    /// The file is one NotchFlow owns outright, so the same whole-file byte
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
        let generated = try generatedPlugin()
        let existingData = try fileSystem.readFile(at: pluginURL)
        guard existingData != generated.data else {
            return
        }

        try fileSystem.createDirectory(at: pluginURL.deletingLastPathComponent())
        if let existingData, try fileSystem.readFile(at: backupURL) == nil {
            try fileSystem.writeFileAtomically(existingData, to: backupURL)
        }
        try fileSystem.writeFileAtomically(generated.data, to: pluginURL)
    }

    public func uninstall() throws {
        if let backupData = try fileSystem.readFile(at: backupURL) {
            guard try fileSystem.readFile(at: pluginURL) == generatedPlugin().data else {
                throw OpenCodePluginInstallerError.pluginChangedSinceInstall
            }
            try fileSystem.writeFileAtomically(backupData, to: pluginURL)
            try fileSystem.removeFile(at: backupURL)
            return
        }

        guard let pluginData = try fileSystem.readFile(at: pluginURL) else {
            return
        }
        let generatedData = try generatedPlugin().data
        guard pluginData == generatedData else {
            throw OpenCodePluginInstallerError.pluginChangedSinceInstall
        }
        try fileSystem.removeFile(at: pluginURL)
        try removeEmptyParents()
    }

    private func generatedPlugin() throws -> (text: String, data: Data) {
        let text = HookSnippetGenerator().openCodePluginFile()
        guard text.contains("export const NotchFlowPlugin: Plugin"),
            text.contains("agentId: \"opencode\""),
            text.contains("session.created"),
            text.contains("tool.execute.before"),
            let data = text.data(using: .utf8)
        else {
            throw OpenCodePluginInstallerError.invalidGeneratedPlugin
        }
        return (text, data)
    }

    private func removeEmptyParents() throws {
        var parentURL = pluginURL.deletingLastPathComponent()
        for _ in 0..<Self.removableParentCount {
            try fileSystem.removeDirectoryIfEmpty(at: parentURL)
            parentURL.deleteLastPathComponent()
        }
    }
}
