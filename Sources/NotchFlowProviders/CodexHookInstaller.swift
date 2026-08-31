import Foundation
import NotchFlowCore

public enum CodexHookInstallerError: Error, Equatable, Sendable {
    case invalidExistingConfiguration
    case invalidGeneratedConfiguration
    case configurationChangedSinceInstall
}

public typealias CodexTOMLSyntaxValidator = @Sendable (String) -> Bool

public protocol CodexHookFileSystem: Sendable {
    func readFile(at url: URL) throws -> Data?
    func createDirectory(at url: URL) throws
    func writeFileAtomically(_ data: Data, to url: URL) throws
    func removeFile(at url: URL) throws
}

public struct FoundationCodexHookFileSystem: CodexHookFileSystem {
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

public struct CodexHookInstaller: Sendable {
    private static let configPath = ".codex/config.toml"
    private static let backupSuffix = ".notchflow-backup"
    private static let rootNotifyPattern = #"(?m)^notify[ \t]*=[ \t]*[^\r\n]*(?:\r?\n|$)"#

    private let fileSystem: any CodexHookFileSystem
    private let syntaxValidator: CodexTOMLSyntaxValidator
    private let configURL: URL
    private let backupURL: URL

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: any CodexHookFileSystem = FoundationCodexHookFileSystem(),
        syntaxValidator: CodexTOMLSyntaxValidator? = nil
    ) {
        self.fileSystem = fileSystem
        self.syntaxValidator = syntaxValidator ?? Self.basicTOMLIsValid
        configURL = homeDirectory.appending(path: Self.configPath)
        backupURL = configURL.appendingPathExtension(
            String(Self.backupSuffix.dropFirst())
        )
    }

    public func proposedConfiguration() throws -> String {
        let existingData = try fileSystem.readFile(at: configURL)
        return try mergedConfiguration(from: existingData).text
    }

    /// The manual-setup fallback's content, produced by the same call `install()`
    /// writes from so the two can never disagree.
    public func manualSetupInstructions() throws -> ManualSetupInstructions {
        ManualSetupInstructions(
            agent: .codex,
            destinationPath: configURL.path,
            snippet: try proposedConfiguration()
        )
    }

    /// Whether `~/.codex/config.toml` already carries our `notify` setting.
    ///
    /// Delegates to `mergedConfiguration(from:)`, the same computation
    /// `install()` gates on, so the query and the mutation can never disagree
    /// about what "installed" means.
    ///
    /// Reads only; it never creates the directory, the backup, or the file.
    public func installationState() -> HookInstallationState {
        do {
            guard let existingData = try fileSystem.readFile(at: configURL) else {
                return .configurationMissing
            }
            return try mergedConfiguration(from: existingData).changed ? .hookAbsent : .hookInstalled
        } catch {
            // A throw here means the bytes are not TOML we can parse, or carry
            // duplicate root `notify` keys — either way the hook state is
            // genuinely unknowable rather than absent.
            return .configurationUnreadable
        }
    }

    public func install() throws {
        let existingData = try fileSystem.readFile(at: configURL)
        let merged = try mergedConfiguration(from: existingData)
        guard merged.changed else {
            return
        }

        try fileSystem.createDirectory(at: configURL.deletingLastPathComponent())
        if let existingData, try fileSystem.readFile(at: backupURL) == nil {
            try fileSystem.writeFileAtomically(existingData, to: backupURL)
        }
        try fileSystem.writeFileAtomically(Data(merged.text.utf8), to: configURL)
    }

    public func uninstall() throws {
        if let backup = try fileSystem.readFile(at: backupURL) {
            _ = try validatedText(from: backup, error: .invalidExistingConfiguration)
            let installedData = Data(try mergedConfiguration(from: backup).text.utf8)
            guard try fileSystem.readFile(at: configURL) == installedData else {
                throw CodexHookInstallerError.configurationChangedSinceInstall
            }
            try fileSystem.writeFileAtomically(backup, to: configURL)
            try fileSystem.removeFile(at: backupURL)
            return
        }

        guard let existingData = try fileSystem.readFile(at: configURL) else {
            return
        }
        let existing = try validatedText(
            from: existingData,
            error: .invalidExistingConfiguration
        )
        let removal = try configurationRemovingGeneratedNotify(from: existing)
        guard removal.changed else {
            return
        }
        if removal.text.isEmpty {
            try fileSystem.removeFile(at: configURL)
            return
        }
        guard syntaxValidator(removal.text) else {
            throw CodexHookInstallerError.invalidGeneratedConfiguration
        }
        try fileSystem.writeFileAtomically(Data(removal.text.utf8), to: configURL)
    }

    private func mergedConfiguration(from existingData: Data?) throws -> (text: String, changed: Bool) {
        let existing: String
        if let existingData {
            existing = try validatedText(
                from: existingData,
                error: .invalidExistingConfiguration
            )
        } else {
            existing = ""
        }

        let generated = generatedNotifySetting()
        let merged = try configurationBySettingRootNotify(generated, in: existing)
        guard syntaxValidator(merged) else {
            throw CodexHookInstallerError.invalidGeneratedConfiguration
        }
        return (merged, merged != existing)
    }

    private func generatedNotifySetting() -> String {
        HookSnippetGenerator().codexNotifyFragment()
    }

    private func configurationBySettingRootNotify(
        _ generated: String,
        in existing: String
    ) throws -> String {
        let expression = try NSRegularExpression(pattern: Self.rootNotifyPattern)
        let rootRange = NSRange(existing.startIndex..<rootTableEnd(in: existing), in: existing)
        let matches = expression.matches(in: existing, range: rootRange)

        if matches.count > 1 {
            throw CodexHookInstallerError.invalidExistingConfiguration
        }
        if let match = matches.first, let range = Range(match.range, in: existing) {
            return existing.replacingCharacters(in: range, with: generated)
        }
        if existing.isEmpty {
            return generated
        }

        let tableStart = rootTableEnd(in: existing)
        let prefix = existing[..<tableStart]
        let separator = prefix.isEmpty || prefix.hasSuffix("\n") ? "" : "\n"
        let insertion = separator + generated
        return String(existing[..<tableStart]) + insertion + String(existing[tableStart...])
    }

    private func configurationRemovingGeneratedNotify(
        from existing: String
    ) throws -> (text: String, changed: Bool) {
        let expression = try NSRegularExpression(pattern: Self.rootNotifyPattern)
        let rootRange = NSRange(existing.startIndex..<rootTableEnd(in: existing), in: existing)
        let matches = expression.matches(in: existing, range: rootRange)

        guard matches.count <= 1 else {
            throw CodexHookInstallerError.invalidExistingConfiguration
        }
        guard
            let match = matches.first,
            let range = Range(match.range, in: existing),
            String(existing[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                == generatedNotifySetting().trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return (existing, false)
        }

        return (existing.replacingCharacters(in: range, with: ""), true)
    }

    private func rootTableEnd(in text: String) -> String.Index {
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                return lineStart
            }
            lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
        }
        return text.endIndex
    }

    private func validatedText(
        from data: Data,
        error: CodexHookInstallerError
    ) throws -> String {
        guard let text = String(bytes: data, encoding: .utf8), syntaxValidator(text) else {
            throw error
        }
        return text
    }

    private static func basicTOMLIsValid(_ text: String) -> Bool {
        var scanner = TOMLSyntaxScanner(text: text)
        return scanner.isValid()
    }
}
