import Foundation
import NotchFlowCore
import os

public enum CodexHookInstallerError: Error, Equatable, Sendable {
    case invalidExistingConfiguration
    case invalidGeneratedConfiguration
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
    private static let logger = Logger(
        subsystem: "com.notchflow.NotchFlow",
        category: "codex-installer"
    )
    private static let rootNotifyPattern = #"(?m)^[ \t]*notify[ \t]*="#
    /// Matched from the generator's own constant rather than restated here: a
    /// second copy of the token is how the installer stopped recognising the
    /// hook it had just written.
    private static let lifecycleHookMarker = HookSnippetGenerator.codexLifecycleHookMarker
    private static let legacyLifecycleHookMarkers = HookSnippetGenerator.previousCodexLifecycleHookMarkers

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
            if try fileSystem.readFile(at: configURL) == installedData {
                try fileSystem.writeFileAtomically(backup, to: configURL)
                try fileSystem.removeFile(at: backupURL)
                return
            }
            // The configuration moved on after installation — a hand edit, or a
            // notify an earlier version wrote. Restoring the backup would discard
            // that, so only the managed notify is removed below and the backup
            // stays.
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

    /// Whether this handler is one of ours — this version's or an earlier one.
    ///
    /// Earlier markers stay recognised so an upgrade replaces the old handler
    /// instead of leaving it beside the new one, firing every event twice.
    private func isManagedLifecycleHandler(_ handler: [String: Any]) -> Bool {
        guard let command = handler["command"] as? String else { return false }
        return command.contains(Self.lifecycleHookMarker)
            || Self.legacyLifecycleHookMarkers.contains(where: command.contains)
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
            if isCurrentManagedNotify(assignment.arguments) {
                return existing
            }
            // Ours, but wrapped by another tool's notifier. The chain is that
            // tool's to own, so only NotchFlow's element inside it is touched —
            // and only when it is a previous version's. Left alone, that
            // element kept the launch fallback it was written with: every turn
            // Codex reported through the wrapper relaunched a quit NotchFlow.
            if containsNestedManagedNotify(assignment.arguments) {
                let upgraded = try upgradingNestedManagedNotify(in: assignment.arguments)
                guard upgraded != assignment.arguments else { return existing }
                return existing.replacingCharacters(
                    in: assignment.range,
                    with: try plainNotifySetting(upgraded)
                )
            }

            // A `notify` an earlier NotchFlow wrote is replaced rather than
            // forwarded to — forwarding to our own previous command would
            // deliver every turn twice, once through each version.
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
            let replacement = forwarded.isEmpty ? "" : try plainNotifySetting(forwarded)
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
                let argument: String
                do {
                    argument = try JSONDecoder().decode(String.self, from: Data(token.utf8))
                } catch let decodeError {
                    // The typed error aborts the install; the decode error says
                    // which token is malformed and why, which a bare `try?`
                    // discarded.
                    Self.logger.error(
                        "Notify token \(token, privacy: .public) in \(self.configURL.path, privacy: .public) is not a valid JSON string: \(String(describing: decodeError), privacy: .public)"
                    )
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

    /// Whether these arguments are the `notify` command this version writes.
    ///
    /// The interpreter is matched by name rather than by full path: the
    /// generator moved from `python3` to `/usr/bin/python3`, and an equality
    /// check against either spelling rejects the other.
    private func isCurrentManagedNotify(_ arguments: [String]) -> Bool {
        arguments.count >= 3
            && arguments[0].hasSuffix("python3")
            && arguments[2].contains(HookSnippetGenerator.codexNotifyMarker)
    }

    /// Whether these arguments are a `notify` command an *earlier* NotchFlow
    /// wrote. Recognising them is what lets an upgrade replace the old command
    /// rather than refuse to touch a file it does not understand.
    private func isLegacyManagedNotify(_ arguments: [String]) -> Bool {
        let command = arguments.joined(separator: " ")
        guard command.contains("notchflow://ai-status") else { return false }
        return command.contains(#"agentId":"codex"#)
            || command.contains("notchflow_codex_notify_")
    }

    private func containsNestedManagedNotify(
        _ arguments: [String],
        depth: Int = 0
    ) -> Bool {
        guard depth < 4 else { return false }
        for argument in arguments {
            // The decode is a probe, not an expectation: every plain argument
            // (a notifier path, "turn-ended") fails it by design, so nil here
            // is the answer "not a nested command chain", not a failure to
            // surface.
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
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch let decodeError {
            // The payload under our own marker is corrupt — a hand-edited
            // config or a truncated write. Dropping the chain is the only
            // recovery, but the loss is logged so the notify replacement
            // that follows stays traceable to it.
            Self.logger.error(
                "Forwarded notify payload in \(self.configURL.path, privacy: .public) is not decodable as a JSON string array: \(String(describing: decodeError), privacy: .public)"
            )
            return nil
        }
    }

    /// The chain with every nested NotchFlow notify an earlier version wrote
    /// replaced by this version's, and everything else exactly as it was.
    private func upgradingNestedManagedNotify(
        in arguments: [String],
        depth: Int = 0
    ) throws -> [String] {
        guard depth < 4 else { return arguments }
        return try arguments.map { argument in
            // The decode is a probe, as in `containsNestedManagedNotify`: a
            // plain argument fails it by design.
            guard
                let data = argument.data(using: .utf8),
                let nested = try? JSONDecoder().decode([String].self, from: data),
                nested != arguments
            else {
                return argument
            }
            if isCurrentManagedNotify(nested) {
                return argument
            }
            let replacement: [String]
            if isLegacyManagedNotify(nested) {
                replacement = try currentManagedNotifyArguments()
            } else {
                replacement = try upgradingNestedManagedNotify(in: nested, depth: depth + 1)
                guard replacement != nested else { return argument }
            }
            return try encodedNotifyArguments(replacement)
        }
    }

    private func currentManagedNotifyArguments() throws -> [String] {
        let literal = generatedNotifySetting()
            .dropFirst("notify = ".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try JSONDecoder().decode([String].self, from: Data(literal.utf8))
        } catch {
            throw CodexHookInstallerError.invalidGeneratedConfiguration
        }
    }

    private func plainNotifySetting(_ arguments: [String]) throws -> String {
        "notify = \(try encodedNotifyArguments(arguments))\n"
    }

    private func encodedNotifyArguments(_ arguments: [String]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(arguments)
        } catch let encodeError {
            // A plain string array always encodes; reaching here means the
            // forwarded chain holds something JSON cannot represent, and the
            // replacement we were about to write would be garbage.
            Self.logger.error(
                "Codex notify arguments failed to encode: \(String(describing: encodeError), privacy: .public)"
            )
            throw CodexHookInstallerError.invalidGeneratedConfiguration
        }
        return String(decoding: data, as: UTF8.self)
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
