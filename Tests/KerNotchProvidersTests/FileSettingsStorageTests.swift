import Foundation
import KerNotchCore
import Testing

@testable import KerNotchProviders

/// The settings file against a real, per-test temporary directory — its point is
/// what lands on disk: that it survives a relaunch, keeps registered defaults
/// out of the file, stays owner-only, and never destroys a file it cannot read.
@Suite("FileSettingsStorage")
@MainActor
struct FileSettingsStorageTests {
    private static func withFile(_ body: (URL) throws -> Void) rethrows {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kernotch-settings-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root.appendingPathComponent("KerNotch", isDirectory: true).appendingPathComponent("settings.json"))
    }

    private static func storedObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("a setting survives a relaunch")
    func persistsAcrossInstances() throws {
        try Self.withFile { url in
            let first = FileSettingsStorage(fileURL: url)
            first.set(true, forKey: "com.kernotch.settings.integrations.discord.enabled")
            first.set("tr", forKey: "com.kernotch.settings.general.languageOverride")

            let relaunched = FileSettingsStorage(fileURL: url)

            #expect(relaunched.object(forKey: "com.kernotch.settings.integrations.discord.enabled") as? Bool == true)
            #expect(relaunched.object(forKey: "com.kernotch.settings.general.languageOverride") as? String == "tr")
        }
    }

    /// Defaults are code, not data: writing them out would freeze today's
    /// defaults into every user's file and stop a later release changing them.
    @Test("registered defaults are answered but never written to the file")
    func defaultsStayOutOfTheFile() throws {
        try Self.withFile { url in
            let storage = FileSettingsStorage(fileURL: url)
            storage.register(defaults: ["com.kernotch.settings.providers.music.enabled": true])
            storage.set(false, forKey: "com.kernotch.settings.providers.timer.enabled")

            #expect(storage.object(forKey: "com.kernotch.settings.providers.music.enabled") as? Bool == true)
            let stored = try Self.storedObject(at: url)
            #expect(stored.keys.contains("com.kernotch.settings.providers.music.enabled") == false)
        }
    }

    @Test("a stored value overrides its registered default")
    func storedValueWins() throws {
        try Self.withFile { url in
            let storage = FileSettingsStorage(fileURL: url)
            storage.register(defaults: ["key": true])

            storage.set(false, forKey: "key")

            #expect(storage.object(forKey: "key") as? Bool == false)
        }
    }

    @Test("removing a setting, or setting it to nil, falls back to its default")
    func removalFallsBack() throws {
        try Self.withFile { url in
            let storage = FileSettingsStorage(fileURL: url)
            storage.register(defaults: ["key": true])
            storage.set(false, forKey: "key")
            storage.set("x", forKey: "other")

            storage.removeObject(forKey: "key")
            storage.set(nil, forKey: "other")

            #expect(storage.object(forKey: "key") as? Bool == true)
            #expect(FileSettingsStorage(fileURL: url).object(forKey: "other") == nil)
        }
    }

    @Test("keeps the file readable by the user alone")
    func ownerOnlyPermissions() throws {
        try Self.withFile { url in
            FileSettingsStorage(fileURL: url).set(true, forKey: "key")

            let manager = FileManager.default
            let filePermissions = try manager.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
            let directoryPath = url.deletingLastPathComponent().path
            let directoryPermissions = try manager.attributesOfItem(atPath: directoryPath)[.posixPermissions] as? Int
            #expect(filePermissions == 0o600)
            #expect(directoryPermissions == 0o700)
        }
    }

    private static func setAsideCopies(beside url: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("settings.unreadable-") }
    }

    @Test("sets an unparseable file aside instead of overwriting it")
    func setsAsideUnparseableFile() throws {
        try Self.withFile { url in
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("{ not json".utf8).write(to: url)

            let storage = FileSettingsStorage(fileURL: url)
            storage.set(true, forKey: "key")

            let copies = try Self.setAsideCopies(beside: url)
            #expect(copies.count == 1)
            #expect(try copies.first.map { try String(contentsOf: $0, encoding: .utf8) } == "{ not json")
            #expect(FileSettingsStorage(fileURL: url).object(forKey: "key") as? Bool == true)
        }
    }

    @Test("a second unparseable file never replaces the first set-aside copy")
    func keepsEverySetAsideCopy() throws {
        try Self.withFile { url in
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("first".utf8).write(to: url)
            _ = FileSettingsStorage(fileURL: url)
            try Data("second".utf8).write(to: url)
            _ = FileSettingsStorage(fileURL: url)

            #expect(try Self.setAsideCopies(beside: url).count == 2)
        }
    }

    /// A file that exists but cannot be read — restored from a backup with the
    /// wrong owner, say — may still hold every setting. Writing over it would
    /// make that loss permanent.
    @Test("never writes over a file it cannot read")
    func leavesUnreadableFileAlone() throws {
        try Self.withFile { url in
            let original = FileSettingsStorage(fileURL: url)
            original.set(true, forKey: "com.kernotch.settings.general.launchAtLogin")
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }

            let storage = FileSettingsStorage(fileURL: url)
            storage.set(false, forKey: "com.kernotch.settings.general.showMenuBarIcon")

            #expect(storage.isSavingEnabled == false)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let kept = FileSettingsStorage(fileURL: url)
            #expect(kept.object(forKey: "com.kernotch.settings.general.launchAtLogin") as? Bool == true)
            #expect(kept.object(forKey: "com.kernotch.settings.general.showMenuBarIcon") == nil)
        }
    }

    /// The settings window writes every value back whenever it appears.
    @Test("setting a value the file already holds writes nothing")
    func unchangedValueWritesNothing() throws {
        try Self.withFile { url in
            let storage = FileSettingsStorage(fileURL: url)
            storage.set(true, forKey: "key")
            try FileManager.default.removeItem(at: url)

            storage.set(true, forKey: "key")

            #expect(FileManager.default.fileExists(atPath: url.path) == false)
        }
    }

    @Test("echoing a default the user never changed neither writes nor freezes it")
    func echoedDefaultIsNotStored() throws {
        try Self.withFile { url in
            let storage = FileSettingsStorage(fileURL: url)
            storage.register(defaults: ["key": true])

            storage.set(true, forKey: "key")
            storage.register(defaults: ["key": false])

            #expect(FileManager.default.fileExists(atPath: url.path) == false)
            #expect(storage.object(forKey: "key") as? Bool == false)
        }
    }

    /// The language restart and a watchdog relaunch both start a new instance
    /// before the old one exits.
    @Test("two running instances keep each other's changes")
    func instancesMergeTheirChanges() throws {
        try Self.withFile { url in
            let first = FileSettingsStorage(fileURL: url)
            let second = FileSettingsStorage(fileURL: url)

            first.set(true, forKey: "com.kernotch.settings.integrations.discord.enabled")
            second.set(false, forKey: "com.kernotch.settings.providers.music.enabled")

            let relaunched = FileSettingsStorage(fileURL: url)
            #expect(relaunched.object(forKey: "com.kernotch.settings.integrations.discord.enabled") as? Bool == true)
            #expect(relaunched.object(forKey: "com.kernotch.settings.providers.music.enabled") as? Bool == false)
        }
    }

    @Test("refuses a value that has no JSON form rather than corrupting the file")
    func refusesNonJSONValues() throws {
        try Self.withFile { url in
            let storage = FileSettingsStorage(fileURL: url)
            storage.set(true, forKey: "kept")

            storage.set(Date(), forKey: "date")

            #expect(storage.object(forKey: "date") == nil)
            #expect(FileSettingsStorage(fileURL: url).object(forKey: "kept") as? Bool == true)
        }
    }
}

@Suite("Settings import from macOS preferences")
@MainActor
struct SettingsPreferencesImportTests {
    private static func withPreferences(_ body: (UserDefaults, String, URL) throws -> Void) throws {
        let domain = "com.kernotch.tests.settings-import.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kernotch-import-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        try body(defaults, domain, root.appendingPathComponent("settings.json"))
    }

    private static func settingsKeys(in defaults: UserDefaults, domain: String) -> [String] {
        (defaults.persistentDomain(forName: domain) ?? [:]).keys.filter { $0.hasPrefix(SettingsKeys.namePrefix) }
    }

    @Test("moves KerNotch's settings into the file and out of the preferences domain")
    func movesSettings() throws {
        try Self.withPreferences { defaults, domain, url in
            defaults.set(true, forKey: SettingsKey<Bool>.enableDiscord.name)
            defaults.set(false, forKey: SettingsKey<Bool>.showMusic.name)

            let storage = FileSettingsStorage(fileURL: url)
            storage.importPreferences(from: defaults, domain: domain)
            let store = SettingsStore(storage: storage)

            #expect(store[.enableDiscord])
            #expect(store[.showMusic] == false)
            #expect(Self.settingsKeys(in: defaults, domain: domain).isEmpty)
            let relaunched = FileSettingsStorage(fileURL: url)
            #expect(relaunched.object(forKey: SettingsKey<Bool>.enableDiscord.name) as? Bool == true)
        }
    }

    /// macOS reads the app's language from the preferences domain at launch, so
    /// that key must stay where it is.
    @Test("leaves keys outside KerNotch's settings where macOS reads them")
    func leavesForeignKeys() throws {
        try Self.withPreferences { defaults, domain, url in
            defaults.set(["tr"], forKey: "AppleLanguages")
            defaults.set(true, forKey: SettingsKey<Bool>.enableDiscord.name)

            FileSettingsStorage(fileURL: url).importPreferences(from: defaults, domain: domain)

            #expect(defaults.persistentDomain(forName: domain)?["AppleLanguages"] as? [String] == ["tr"])
        }
    }

    /// The documented CPU watchdog kill switch is a `defaults write`; it has to
    /// keep working once settings live in the file.
    @Test("a value written into the preferences domain by hand wins at the next launch")
    func handWrittenPreferenceWins() throws {
        try Self.withPreferences { defaults, domain, url in
            FileSettingsStorage(fileURL: url).set(true, forKey: "unrelated")
            FileSettingsStorage(fileURL: url).set(false, forKey: SettingsKey<Bool>.cpuWatchdogDisabled.name)
            defaults.set(true, forKey: SettingsKey<Bool>.cpuWatchdogDisabled.name)

            let storage = FileSettingsStorage(fileURL: url)
            storage.importPreferences(from: defaults, domain: domain)

            #expect(SettingsStore(storage: storage)[.cpuWatchdogDisabled])
        }
    }

    /// The first launch of the update is the one moment every setting exists
    /// in only one place. If the file cannot take them, they must stay there.
    @Test("keeps every setting in the preferences domain when the file cannot be written")
    func failedWriteKeepsPreferences() throws {
        try Self.withPreferences { defaults, domain, url in
            defaults.set(true, forKey: SettingsKey<Bool>.enableDiscord.name)
            let blocker = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: blocker.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: blocker)

            FileSettingsStorage(fileURL: url).importPreferences(from: defaults, domain: domain)

            #expect(Self.settingsKeys(in: defaults, domain: domain) == [SettingsKey<Bool>.enableDiscord.name])
        }
    }

    @Test("leaves a value with no JSON form in the preferences domain")
    func keepsUnimportableValues() throws {
        try Self.withPreferences { defaults, domain, url in
            let dateKey = SettingsKeys.namePrefix + "tests.date"
            defaults.set(Date(timeIntervalSinceReferenceDate: 0), forKey: dateKey)
            defaults.set(true, forKey: SettingsKey<Bool>.enableDiscord.name)

            FileSettingsStorage(fileURL: url).importPreferences(from: defaults, domain: domain)

            #expect(Self.settingsKeys(in: defaults, domain: domain) == [dateKey])
        }
    }

    @Test("with nothing to import, the file is left untouched")
    func nothingToImport() throws {
        try Self.withPreferences { defaults, domain, url in
            FileSettingsStorage(fileURL: url).importPreferences(from: defaults, domain: domain)

            #expect(FileManager.default.fileExists(atPath: url.path) == false)
        }
    }
}
