import Foundation
import KerNotchCore
import os

/// The settings store's backing file: one owner-only JSON document in KerNotch's
/// Application Support directory, beside the Discord credentials and the
/// watchdog's records.
///
/// Keeping every piece of state KerNotch owns in that one directory is what
/// makes backing it up, resetting it, or removing it a single-folder operation.
/// Only what macOS insists on reading elsewhere stays elsewhere — the app's
/// language (`AppleLanguages`) and the CPU reports under `~/Library/Logs`.
///
/// Three rules keep the file from ever costing the user their settings:
/// - A file that exists but cannot be read is never written over. A file that
///   cannot be parsed is set aside under a name of its own before anything new
///   is saved, and if it cannot be moved, saving stays off for the session.
/// - Only a real change is written. Setting a value the file already holds, or
///   a registered default the user never changed, touches nothing — so the
///   settings window echoing every value back costs no writes, and a default
///   the user never chose is not frozen into the file.
/// - A save writes only the keys this instance changed over what is on disk,
///   so a second instance running for a moment — the language restart, a
///   watchdog relaunch — does not revert the other's changes.
@MainActor
public final class FileSettingsStorage: SettingsStorage {
    private static let ownerOnlyFilePermissions = 0o600
    private static let ownerOnlyDirectoryPermissions = 0o700
    private static let logger = Logger(subsystem: "com.kernotch.KerNotch", category: "settings-file")

    public static var defaultFileURL: URL {
        ApplicationDirectories.applicationSupport.appendingPathComponent("settings.json", isDirectory: false)
    }

    private let fileURL: URL
    private var values: [String: Any]
    private var registeredDefaults: [String: Any] = [:]
    /// Keys this instance has changed or removed since its last save.
    private var changedKeys: Set<String> = []
    private var isDirectoryPrepared = false

    /// False when saving could destroy settings that may still be recoverable.
    private(set) var isSavingEnabled: Bool

    public init(fileURL: URL = FileSettingsStorage.defaultFileURL) {
        self.fileURL = fileURL
        (values, isSavingEnabled) = Self.load(from: fileURL)
    }

    public func register(defaults registrationDictionary: [String: Any]) {
        registeredDefaults.merge(registrationDictionary) { _, registered in registered }
    }

    public func object(forKey defaultName: String) -> Any? {
        values[defaultName] ?? registeredDefaults[defaultName]
    }

    public func set(_ value: Any?, forKey defaultName: String) {
        guard let value else {
            removeObject(forKey: defaultName)
            return
        }
        guard JSONSerialization.isValidJSONObject([defaultName: value]) else {
            Self.logger.error("Not storing \(defaultName, privacy: .public): the value has no JSON form")
            return
        }
        guard Self.isChange(value, from: values[defaultName] ?? registeredDefaults[defaultName]) else { return }

        values[defaultName] = value
        changedKeys.insert(defaultName)
        save()
    }

    public func removeObject(forKey defaultName: String) {
        guard values.removeValue(forKey: defaultName) != nil else { return }
        changedKeys.insert(defaultName)
        save()
    }

    /// Moves KerNotch's settings out of its macOS preferences domain and into
    /// the file, in one write.
    ///
    /// Run on every launch rather than once: a value written into the domain by
    /// hand — the documented `defaults write` for the CPU watchdog's kill switch
    /// — is taken in at the next launch the same way, and wins, because it is
    /// the most recent thing anyone asked for.
    ///
    /// Nothing leaves the domain unless it reached the file. A write that fails
    /// leaves every key where it was, and a value with no JSON form is not
    /// imported or removed at all. Keys outside the settings namespace, such as
    /// `AppleLanguages`, are left where macOS reads them.
    public func importPreferences(from defaults: UserDefaults, domain: String) {
        guard var preferences = defaults.persistentDomain(forName: domain) else { return }

        let importable = preferences.filter { key, value in
            key.hasPrefix(SettingsKeys.namePrefix) && JSONSerialization.isValidJSONObject([key: value])
        }
        guard importable.isEmpty == false else { return }

        values.merge(importable) { _, imported in imported }
        changedKeys.formUnion(importable.keys)
        guard save() else { return }

        for key in importable.keys {
            preferences.removeValue(forKey: key)
        }
        defaults.setPersistentDomain(preferences, forName: domain)
    }

    /// Writes this instance's changes over the file as it now stands on disk.
    @discardableResult
    private func save() -> Bool {
        guard isSavingEnabled else { return false }

        do {
            try prepareDirectory()
            let (onDisk, isReadable) = Self.load(from: fileURL)
            guard isReadable else {
                isSavingEnabled = false
                return false
            }

            var merged = onDisk
            for key in changedKeys {
                merged[key] = values[key]
            }
            let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: Self.ownerOnlyFilePermissions],
                ofItemAtPath: fileURL.path
            )

            values = merged
            changedKeys.removeAll()
            return true
        } catch {
            Self.logger.error("Writing the settings file failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func prepareDirectory() throws {
        guard isDirectoryPrepared == false else { return }

        let directory = fileURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.ownerOnlyDirectoryPermissions]
        )
        // Applied even when the directory already existed, since it is the
        // permission that keeps other accounts out.
        try fileManager.setAttributes(
            [.posixPermissions: Self.ownerOnlyDirectoryPermissions],
            ofItemAtPath: directory.path
        )
        isDirectoryPrepared = true
    }

    /// Whether storing `value` would change what a read returns. Compared as
    /// Foundation objects, the form both the file and the settings keys use.
    private static func isChange(_ value: Any, from current: Any?) -> Bool {
        guard let current = current as? NSObject, let value = value as? NSObject else { return true }
        return current.isEqual(value) == false
    }

    /// The file's settings, and whether it is safe to write over it.
    ///
    /// No file is a first launch. A file that cannot be read is left alone and
    /// saving turned off. A file that cannot be parsed is moved aside under a
    /// timestamped name, so a second bad file never replaces the first copy.
    private static func load(from fileURL: URL) -> ([String: Any], Bool) {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return ([:], true)
        } catch {
            let reason = String(describing: error)
            logger.error("The settings file could not be read; saving is off: \(reason, privacy: .public)")
            return ([:], false)
        }

        if let values = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return (values, true)
        }

        let setAside = fileURL.deletingLastPathComponent()
            .appendingPathComponent(
                "settings.unreadable-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).json"
            )
        do {
            try FileManager.default.moveItem(at: fileURL, to: setAside)
        } catch {
            logger.error("An unparseable settings file could not be set aside; saving is off")
            return ([:], false)
        }
        let name = setAside.lastPathComponent
        logger.error("The settings file could not be parsed and was set aside as \(name, privacy: .public)")
        return ([:], true)
    }
}
