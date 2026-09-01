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
    private static let hooksPath = ".codex/hooks.json"
    private static let backupSuffix = ".notchflow-backup"
    private static let rootNotifyPattern = #"(?m)^[ \t]*notify[ \t]*="#
    private static let lifecycleHookMarker = "notchflow_codex_hook_v1=True"

    private struct RootNotifyAssignment {
        let range: Range<String.Index>
        let arguments: [String]
    }

    private let fileSystem: any CodexHookFileSystem
    private let syntaxValidator: CodexTOMLSyntaxValidator
    private let configURL: URL
    private let hooksURL: URL
    private let backupURL: URL

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: any CodexHookFileSystem = FoundationCodexHookFileSystem(),
        syntaxValidator: CodexTOMLSyntaxValidator? = nil
    ) {
        self.fileSystem = fileSystem
        self.syntaxValidator = syntaxValidator ?? Self.basicTOMLIsValid
        configURL = homeDirectory.appending(path: Self.configPath)
        hooksURL = homeDirectory.appending(path: Self.hooksPath)
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
            destinationPath: hooksURL.path,
            snippet: String(
                decoding: try lifecycleHooksByInstalling(
                    in: fileSystem.readFile(at: hooksURL)
                ).data,
                as: UTF8.self
            )
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
            let notifyIsInstalled = try mergedConfiguration(from: existingData).changed == false
            let lifecycleHooksAreInstalled = try lifecycleHooksAreInstalled(
                in: fileSystem.readFile(at: hooksURL)
            )
            return notifyIsInstalled && lifecycleHooksAreInstalled
                ? .hookInstalled
                : .hookAbsent
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
        let existingHooksData = try fileSystem.readFile(at: hooksURL)
        let mergedHooks = try lifecycleHooksByInstalling(in: existingHooksData)
        guard merged.changed || mergedHooks.changed else {
            return
        }

        try fileSystem.createDirectory(at: configURL.deletingLastPathComponent())
        if merged.changed {
            if let existingData, try fileSystem.readFile(at: backupURL) == nil {
                try fileSystem.writeFileAtomically(existingData, to: backupURL)
            }
            try fileSystem.writeFileAtomically(Data(merged.text.utf8), to: configURL)
        }
        if mergedHooks.changed {
            try fileSystem.writeFileAtomically(mergedHooks.data, to: hooksURL)
        }
    }

    public func uninstall() throws {
        try uninstallNotify()
        try uninstallLifecycleHooks()
    }

    private func uninstallNotify() throws {
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

    private func lifecycleHooksByInstalling(
        in existingData: Data?
    ) throws -> (data: Data, changed: Bool) {
        var document = try lifecycleHooksDocument(from: existingData)
        var hooks = try lifecycleHookMap(in: document)
        let generatedHooks = try generatedLifecycleHooks()

        for event in generatedHooks.keys.sorted() {
            let existingGroups = try lifecycleHookGroups(for: event, in: hooks)
            let foreignGroups = try removingManagedLifecycleHandlers(from: existingGroups)
            hooks[event] = foreignGroups + (generatedHooks[event] ?? [])
        }

        document["hooks"] = hooks
        let data = try encodedLifecycleHooksDocument(document)
        return (data, existingData.map { $0 == data } != true)
    }

    private func lifecycleHooksAreInstalled(in data: Data?) throws -> Bool {
        guard let data else { return false }
        let document = try lifecycleHooksDocument(from: data)
        let hooks = try lifecycleHookMap(in: document)
        let generatedHooks = try generatedLifecycleHooks()

        for event in generatedHooks.keys {
            let expectedCommand = try managedLifecycleCommand(
                in: generatedHooks[event] ?? []
            )
            let installedHandlers = try lifecycleHookGroups(for: event, in: hooks)
                .flatMap { group -> [[String: Any]] in
                    guard let handlers = group["hooks"] as? [[String: Any]] else {
                        throw CodexHookInstallerError.invalidExistingConfiguration
                    }
                    return handlers.filter(isManagedLifecycleHandler)
                }
            guard
                installedHandlers.count == 1,
                installedHandlers[0]["command"] as? String == expectedCommand
            else {
                return false
            }
        }
        return true
    }

    private func uninstallLifecycleHooks() throws {
        guard let existingData = try fileSystem.readFile(at: hooksURL) else {
            return
        }
        var document = try lifecycleHooksDocument(from: existingData)
        var hooks = try lifecycleHookMap(in: document)
        var changed = false

        for event in hooks.keys.sorted() {
            let existingGroups = try lifecycleHookGroups(for: event, in: hooks)
            let managedHandlerCount = try existingGroups.reduce(into: 0) { count, group in
                guard let handlers = group["hooks"] as? [[String: Any]] else {
                    throw CodexHookInstallerError.invalidExistingConfiguration
                }
                count += handlers.filter(isManagedLifecycleHandler).count
            }
            guard managedHandlerCount > 0 else { continue }
            let foreignGroups = try removingManagedLifecycleHandlers(from: existingGroups)
            if foreignGroups.isEmpty {
                hooks[event] = nil
            } else {
                hooks[event] = foreignGroups
            }
            changed = true
        }

        guard changed else { return }
        document["hooks"] = hooks
        if hooks.isEmpty, Set(document.keys) == ["hooks"] {
            try fileSystem.removeFile(at: hooksURL)
            return
        }
        try fileSystem.writeFileAtomically(
            encodedLifecycleHooksDocument(document),
            to: hooksURL
        )
    }

    private func lifecycleHooksDocument(from data: Data?) throws -> [String: Any] {
        guard let data else {
            return ["hooks": [String: Any]()]
        }
        do {
            guard
                let document = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw CodexHookInstallerError.invalidExistingConfiguration
            }
            _ = try lifecycleHookMap(in: document)
            return document
        } catch let error as CodexHookInstallerError {
            throw error
        } catch {
            throw CodexHookInstallerError.invalidExistingConfiguration
        }
    }

    private func lifecycleHookMap(in document: [String: Any]) throws -> [String: Any] {
        guard let value = document["hooks"] else { return [:] }
        guard let hooks = value as? [String: Any] else {
            throw CodexHookInstallerError.invalidExistingConfiguration
        }
        return hooks
    }

    private func generatedLifecycleHooks() throws -> [String: [[String: Any]]] {
        let data = Data(HookSnippetGenerator().codexLifecycleHooksFragment().utf8)
        do {
            guard
                let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let rawHooks = document["hooks"] as? [String: Any]
            else {
                throw CodexHookInstallerError.invalidGeneratedConfiguration
            }
            return try rawHooks.reduce(into: [:]) { hooks, pair in
                guard let groups = pair.value as? [[String: Any]] else {
                    throw CodexHookInstallerError.invalidGeneratedConfiguration
                }
                hooks[pair.key] = groups
            }
        } catch let error as CodexHookInstallerError {
            throw error
        } catch {
            throw CodexHookInstallerError.invalidGeneratedConfiguration
        }
    }

    private func lifecycleHookGroups(
        for event: String,
        in hooks: [String: Any]
    ) throws -> [[String: Any]] {
        guard let value = hooks[event] else { return [] }
        guard let groups = value as? [[String: Any]] else {
            throw CodexHookInstallerError.invalidExistingConfiguration
        }
        return groups
    }

    private func removingManagedLifecycleHandlers(
        from groups: [[String: Any]]
    ) throws -> [[String: Any]] {
        try groups.compactMap { originalGroup in
            var group = originalGroup
            guard let handlers = group["hooks"] as? [[String: Any]] else {
                throw CodexHookInstallerError.invalidExistingConfiguration
            }
            let foreignHandlers = handlers.filter { !isManagedLifecycleHandler($0) }
            guard !foreignHandlers.isEmpty else { return nil }
            group["hooks"] = foreignHandlers
            return group
        }
    }

    private func managedLifecycleCommand(
        in groups: [[String: Any]]
    ) throws -> String {
        let handlers = try groups.flatMap { group -> [[String: Any]] in
            guard let handlers = group["hooks"] as? [[String: Any]] else {
                throw CodexHookInstallerError.invalidGeneratedConfiguration
            }
            return handlers.filter(isManagedLifecycleHandler)
        }
        guard
            handlers.count == 1,
            let command = handlers[0]["command"] as? String
        else {
            throw CodexHookInstallerError.invalidGeneratedConfiguration
        }
        return command
    }

    private func isManagedLifecycleHandler(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.contains(Self.lifecycleHookMarker) == true
    }

    private func encodedLifecycleHooksDocument(
        _ document: [String: Any]
    ) throws -> Data {
        guard JSONSerialization.isValidJSONObject(document) else {
            throw CodexHookInstallerError.invalidGeneratedConfiguration
        }
        do {
            var data = try JSONSerialization.data(
                withJSONObject: document,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            data.append(contentsOf: Data("\n".utf8))
            return data
        } catch {
            throw CodexHookInstallerError.invalidGeneratedConfiguration
        }
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

        let merged = try configurationBySettingRootNotify(in: existing)
        guard syntaxValidator(merged) else {
            throw CodexHookInstallerError.invalidGeneratedConfiguration
        }
        return (merged, merged != existing)
    }

    private func generatedNotifySetting(forwarding arguments: [String] = []) -> String {
        HookSnippetGenerator().codexNotifyFragment(forwarding: arguments)
    }

    private func configurationBySettingRootNotify(in existing: String) throws -> String {
        if let assignment = try rootNotifyAssignment(in: existing) {
            if containsManagedNotify(assignment.arguments) {
                return existing
            }
            let forwardedArguments = isLegacyManagedNotify(assignment.arguments)
                ? []
                : assignment.arguments
            return existing.replacingCharacters(
                in: assignment.range,
                with: generatedNotifySetting(forwarding: forwardedArguments)
            )
        }
        if existing.isEmpty {
            return generatedNotifySetting()
        }

        let tableStart = rootTableEnd(in: existing)
        let prefix = existing[..<tableStart]
        let separator = prefix.isEmpty || prefix.hasSuffix("\n") ? "" : "\n"
        let insertion = separator + generatedNotifySetting()
        return String(existing[..<tableStart]) + insertion + String(existing[tableStart...])
    }

    private func configurationRemovingGeneratedNotify(
        from existing: String
    ) throws -> (text: String, changed: Bool) {
        guard let assignment = try rootNotifyAssignment(in: existing) else {
            return (existing, false)
        }

        if containsNestedManagedNotify(assignment.arguments) {
            return (existing, false)
        }
        if isCurrentManagedNotify(assignment.arguments) {
            let forwarded = forwardedArguments(from: assignment.arguments) ?? []
            let replacement = forwarded.isEmpty ? "" : plainNotifySetting(forwarded)
            return (
                existing.replacingCharacters(in: assignment.range, with: replacement),
                true
            )
        }
        guard isLegacyManagedNotify(assignment.arguments) else {
            return (existing, false)
        }

        return (existing.replacingCharacters(in: assignment.range, with: ""), true)
    }

    private func rootNotifyAssignment(in existing: String) throws -> RootNotifyAssignment? {
        let expression = try NSRegularExpression(pattern: Self.rootNotifyPattern)
        let rootRange = NSRange(existing.startIndex..<rootTableEnd(in: existing), in: existing)
        let matches = expression.matches(in: existing, range: rootRange)
        guard matches.count <= 1 else {
            throw CodexHookInstallerError.invalidExistingConfiguration
        }
        guard
            let match = matches.first,
            let matchRange = Range(match.range, in: existing)
        else {
            return nil
        }

        let range = try notifyAssignmentRange(
            startingAt: matchRange.upperBound,
            in: existing
        )
        let arguments = try notifyArguments(in: existing[range])
        return RootNotifyAssignment(
            range: matchRange.lowerBound..<range.upperBound,
            arguments: arguments
        )
    }

    private func notifyAssignmentRange(
        startingAt valueStart: String.Index,
        in text: String
    ) throws -> Range<String.Index> {
        var index = valueStart
        while index < text.endIndex, text[index] == " " || text[index] == "\t" {
            index = text.index(after: index)
        }
        guard index < text.endIndex, text[index] == "[" else {
            throw CodexHookInstallerError.invalidExistingConfiguration
        }

        let arrayStart = index
        var depth = 0
        var quote: Character?
        var escaped = false
        var inComment = false
        while index < text.endIndex {
            let character = text[index]
            if inComment {
                inComment = character != "\n"
            } else if let activeQuote = quote {
                if activeQuote == "\"", character == "\\", escaped == false {
                    escaped = true
                } else {
                    if character == activeQuote, escaped == false {
                        quote = nil
                    }
                    escaped = false
                }
            } else if character == "#" {
                inComment = true
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
                if depth == 0 {
                    var end = text.index(after: index)
                    while end < text.endIndex, text[end] != "\n" {
                        guard text[end] == " " || text[end] == "\t" || text[end] == "#" else {
                            throw CodexHookInstallerError.invalidExistingConfiguration
                        }
                        if text[end] == "#" {
                            end = text[end...].firstIndex(of: "\n") ?? text.endIndex
                            break
                        }
                        end = text.index(after: end)
                    }
                    if end < text.endIndex {
                        end = text.index(after: end)
                    }
                    return arrayStart..<end
                }
            }
            index = text.index(after: index)
        }
        throw CodexHookInstallerError.invalidExistingConfiguration
    }

    private func notifyArguments(in assignment: Substring) throws -> [String] {
        guard
            let arrayStart = assignment.firstIndex(of: "["),
            let arrayEnd = assignment.lastIndex(of: "]"),
            arrayStart < arrayEnd
        else {
            throw CodexHookInstallerError.invalidExistingConfiguration
        }

        var index = assignment.index(after: arrayStart)
        var arguments: [String] = []
        while index < arrayEnd {
            skipNotifySeparators(in: assignment, index: &index, end: arrayEnd)
            guard index < arrayEnd else { break }
            let quote = assignment[index]
            guard quote == "\"" || quote == "'" else {
                throw CodexHookInstallerError.invalidExistingConfiguration
            }
            let tokenStart = index
            index = assignment.index(after: index)
            var escaped = false
            while index < arrayEnd {
                let character = assignment[index]
                if quote == "\"", character == "\\", escaped == false {
                    escaped = true
                } else {
                    if character == quote, escaped == false { break }
                    escaped = false
                }
                index = assignment.index(after: index)
            }
            guard index < arrayEnd else {
                throw CodexHookInstallerError.invalidExistingConfiguration
            }
            let tokenEnd = assignment.index(after: index)
            let token = String(assignment[tokenStart..<tokenEnd])
            if quote == "'" {
                arguments.append(String(token.dropFirst().dropLast()))
            } else {
                guard let argument = try? JSONDecoder().decode(String.self, from: Data(token.utf8)) else {
                    throw CodexHookInstallerError.invalidExistingConfiguration
                }
                arguments.append(argument)
            }
            index = tokenEnd
            skipNotifySeparators(in: assignment, index: &index, end: arrayEnd)
            guard index >= arrayEnd || assignment[index] == "," else {
                throw CodexHookInstallerError.invalidExistingConfiguration
            }
            if index < arrayEnd {
                index = assignment.index(after: index)
            }
        }
        return arguments
    }

    private func skipNotifySeparators(
        in text: Substring,
        index: inout String.Index,
        end: String.Index
    ) {
        while index < end {
            if text[index].isWhitespace {
                index = text.index(after: index)
                continue
            }
            if text[index] == "#" {
                index = text[index...].firstIndex(of: "\n") ?? end
                continue
            }
            break
        }
    }

    private func isCurrentManagedNotify(_ arguments: [String]) -> Bool {
        arguments.count >= 3
            && arguments[0] == "python3"
            && arguments[2].contains("notchflow_codex_notify_v2=True")
    }

    private func isLegacyManagedNotify(_ arguments: [String]) -> Bool {
        let command = arguments.joined(separator: " ")
        return command.contains("notchflow://ai-status")
            && command.contains(#"agentId":"codex"#)
    }

    private func containsManagedNotify(_ arguments: [String]) -> Bool {
        isCurrentManagedNotify(arguments)
            || containsNestedManagedNotify(arguments)
            || isLegacyManagedNotify(arguments)
    }

    private func containsNestedManagedNotify(
        _ arguments: [String],
        depth: Int = 0
    ) -> Bool {
        guard depth < 4 else { return false }
        for argument in arguments {
            guard
                let data = argument.data(using: .utf8),
                let nested = try? JSONDecoder().decode([String].self, from: data),
                nested != arguments
            else {
                continue
            }
            if isCurrentManagedNotify(nested)
                || isLegacyManagedNotify(nested)
                || containsNestedManagedNotify(nested, depth: depth + 1)
            {
                return true
            }
        }
        return false
    }

    private func forwardedArguments(from arguments: [String]) -> [String]? {
        guard isCurrentManagedNotify(arguments) else { return nil }
        let script = arguments[2]
        let marker = "notchflow_forward_b64='"
        guard
            let markerRange = script.range(of: marker),
            let end = script[markerRange.upperBound...].firstIndex(of: "'")
        else {
            return nil
        }
        let encoded = String(script[markerRange.upperBound..<end])
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    private func plainNotifySetting(_ arguments: [String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(arguments) else {
            preconditionFailure("Codex notify arguments must encode")
        }
        return "notify = \(String(decoding: data, as: UTF8.self))\n"
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
