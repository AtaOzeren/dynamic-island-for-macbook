import Foundation
import NotchFlowCore

public enum ClaudeCodeHookInstallerError: Error, Equatable, Sendable {
    case invalidExistingSettings
    case invalidGeneratedSettings
    case incompatibleHooksStructure
}

public protocol ClaudeCodeHookFileSystem: Sendable {
    func readFile(at url: URL) throws -> Data?
    func createDirectory(at url: URL) throws
    func writeFileAtomically(_ data: Data, to url: URL) throws
    func removeFile(at url: URL) throws
}

public struct FoundationClaudeCodeHookFileSystem: ClaudeCodeHookFileSystem {
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
}

public struct ClaudeCodeHookInstaller: Sendable {
    private static let settingsPath = ".claude/settings.json"
    private static let backupSuffix = ".notchflow-backup"

    private let fileSystem: any ClaudeCodeHookFileSystem
    private let settingsURL: URL
    private let backupURL: URL

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: any ClaudeCodeHookFileSystem = FoundationClaudeCodeHookFileSystem()
    ) {
        self.fileSystem = fileSystem
        settingsURL = homeDirectory.appending(path: Self.settingsPath)
        backupURL = settingsURL.appendingPathExtension(
            String(Self.backupSuffix.dropFirst())
        )
    }

    public func proposedSettings() throws -> String {
        let existingData = try fileSystem.readFile(at: settingsURL)
        return String(decoding: try mergedSettings(from: existingData).data, as: UTF8.self)
    }

    /// The manual-setup fallback's content, for when the user declines the write
    /// or the sandbox refuses it.
    ///
    /// Goes through `proposedSettings()` rather than re-deriving the text, so the
    /// snippet on screen and the bytes `install()` would write come from one
    /// call and cannot drift apart.
    public func manualSetupInstructions() throws -> ManualSetupInstructions {
        ManualSetupInstructions(
            agent: .claudeCode,
            destinationPath: settingsURL.path,
            snippet: try proposedSettings()
        )
    }

    /// Whether `~/.claude/settings.json` already carries our hook.
    ///
    /// Answers by asking `mergedSettings(from:)` the same question `install()`
    /// asks — "would writing change anything?" — rather than re-deriving what a
    /// hook looks like. A second copy of the merge rules is exactly how a
    /// settings pane starts disagreeing with the installer it drives.
    ///
    /// Reads only; it never creates the directory, the backup, or the file.
    public func installationState() -> HookInstallationState {
        do {
            guard let existingData = try fileSystem.readFile(at: settingsURL) else {
                return .configurationMissing
            }
            return try mergedSettings(from: existingData).changed ? .hookAbsent : .hookInstalled
        } catch {
            // Every throw reachable from here means the file on disk is not
            // settings we can reason about, which is the state's own answer
            // rather than a failure of the query.
            return .configurationUnreadable
        }
    }

    public func install() throws {
        let existingData = try fileSystem.readFile(at: settingsURL)
        let merged = try mergedSettings(from: existingData)
        guard merged.changed else {
            return
        }

        try fileSystem.createDirectory(at: settingsURL.deletingLastPathComponent())
        if let existingData, try fileSystem.readFile(at: backupURL) == nil {
            try fileSystem.writeFileAtomically(existingData, to: backupURL)
        }
        try fileSystem.writeFileAtomically(merged.data, to: settingsURL)
    }

    public func uninstall() throws {
        if let backup = try fileSystem.readFile(at: backupURL) {
            _ = try validatedRoot(from: backup, error: .invalidExistingSettings)
            try fileSystem.writeFileAtomically(backup, to: settingsURL)
            try fileSystem.removeFile(at: backupURL)
            return
        }

        guard let existingData = try fileSystem.readFile(at: settingsURL) else {
            return
        }
        let removal = try settingsRemovingGeneratedHook(from: existingData)
        guard removal.changed else {
            return
        }
        if removal.root.isEmpty {
            try fileSystem.removeFile(at: settingsURL)
            return
        }
        try fileSystem.writeFileAtomically(try encodedSettings(removal.root), to: settingsURL)
    }

    private func mergedSettings(from existingData: Data?) throws -> (data: Data, changed: Bool) {
        var root: [String: Any]
        if let existingData {
            root = try validatedRoot(from: existingData, error: .invalidExistingSettings)
        } else {
            root = [:]
        }

        let generatedRoot = try generatedSettingsRoot()
        let changed = try mergeGeneratedHooks(from: generatedRoot, into: &root)
        if !changed, let existingData {
            return (existingData, false)
        }

        return (try encodedSettings(root), true)
    }

    private func generatedSettingsRoot() throws -> [String: Any] {
        let fragment = HookSnippetGenerator().claudeCodeSettingsFragment()
        return try validatedRoot(
            from: Data(fragment.utf8),
            error: .invalidGeneratedSettings
        )
    }

    private func mergeGeneratedHooks(
        from generatedRoot: [String: Any],
        into root: inout [String: Any]
    ) throws -> Bool {
        let generatedHooks = try hooksDictionary(
            in: generatedRoot,
            missingIsEmpty: false
        )
        var hooks = try hooksDictionary(in: root, missingIsEmpty: true)
        var changed = false

        for (event, generatedValue) in generatedHooks {
            guard let generatedGroups = generatedValue as? [[String: Any]] else {
                throw ClaudeCodeHookInstallerError.invalidGeneratedSettings
            }
            var groups = try hookGroups(for: event, in: hooks)
            for generatedGroup in generatedGroups where !contains(generatedGroup, in: groups) {
                groups.append(generatedGroup)
                changed = true
            }
            hooks[event] = groups
        }

        if changed {
            root["hooks"] = hooks
        }
        return changed
    }

    private func settingsRemovingGeneratedHook(
        from data: Data
    ) throws -> (root: [String: Any], changed: Bool) {
        var root = try validatedRoot(from: data, error: .invalidExistingSettings)
        guard var hooks = root["hooks"] as? [String: Any] else {
            if root["hooks"] == nil {
                return (root, false)
            }
            throw ClaudeCodeHookInstallerError.incompatibleHooksStructure
        }

        let generatedHooks = try hooksDictionary(
            in: generatedSettingsRoot(),
            missingIsEmpty: false
        )
        var changed = false
        for (event, generatedValue) in generatedHooks {
            guard let generatedGroups = generatedValue as? [[String: Any]] else {
                throw ClaudeCodeHookInstallerError.invalidGeneratedSettings
            }
            var groups = try hookGroups(for: event, in: hooks)
            let initialCount = groups.count
            groups.removeAll { group in
                generatedGroups.contains { generatedGroup in
                    jsonObjectsAreEqual(group, generatedGroup)
                }
            }
            guard groups.count != initialCount else {
                continue
            }
            changed = true
            if groups.isEmpty {
                hooks[event] = nil
            } else {
                hooks[event] = groups
            }
        }

        if changed {
            if hooks.isEmpty {
                root["hooks"] = nil
            } else {
                root["hooks"] = hooks
            }
        }
        return (root, changed)
    }

    private func hooksDictionary(
        in root: [String: Any],
        missingIsEmpty: Bool
    ) throws -> [String: Any] {
        guard let value = root["hooks"] else {
            if missingIsEmpty {
                return [:]
            }
            throw ClaudeCodeHookInstallerError.invalidGeneratedSettings
        }
        guard let hooks = value as? [String: Any] else {
            throw ClaudeCodeHookInstallerError.incompatibleHooksStructure
        }
        return hooks
    }

    private func hookGroups(
        for event: String,
        in hooks: [String: Any]
    ) throws -> [[String: Any]] {
        guard let value = hooks[event] else {
            return []
        }
        guard let groups = value as? [[String: Any]] else {
            throw ClaudeCodeHookInstallerError.incompatibleHooksStructure
        }
        return groups
    }

    private func contains(
        _ generatedGroup: [String: Any],
        in groups: [[String: Any]]
    ) -> Bool {
        groups.contains { jsonObjectsAreEqual($0, generatedGroup) }
    }

    private func jsonObjectsAreEqual(
        _ lhs: [String: Any],
        _ rhs: [String: Any]
    ) -> Bool {
        NSDictionary(dictionary: lhs).isEqual(to: rhs)
    }

    private func validatedRoot(
        from data: Data,
        error: ClaudeCodeHookInstallerError
    ) throws -> [String: Any] {
        // Claude Code's documented file is strict JSON. Rejecting JSON5 comments
        // before mutation is safer than accepting and then silently discarding them.
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any]
        else {
            throw error
        }
        return root
    }

    private func encodedSettings(_ root: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(root) else {
            throw ClaudeCodeHookInstallerError.invalidGeneratedSettings
        }
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        _ = try validatedRoot(from: data, error: .invalidGeneratedSettings)
        return data + Data("\n".utf8)
    }
}
