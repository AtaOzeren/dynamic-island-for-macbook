@testable import KerNotchProviders

/// An in-memory settings store, so a presenter test never reads or writes the
/// user's real preferences.
final class DictionarySettingsStorage: SettingsStorage {
    private var values: [String: Any] = [:]
    private var registeredDefaults: [String: Any] = [:]

    func register(defaults: [String: Any]) {
        registeredDefaults.merge(defaults) { current, _ in current }
    }

    func object(forKey defaultName: String) -> Any? {
        values[defaultName] ?? registeredDefaults[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }

    func removeObject(forKey defaultName: String) {
        values.removeValue(forKey: defaultName)
    }
}
