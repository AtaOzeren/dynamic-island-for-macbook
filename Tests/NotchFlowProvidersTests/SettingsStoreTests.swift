import Foundation
import Testing
@testable import NotchFlowCore
@testable import NotchFlowProviders

@Suite("SettingsStore")
@MainActor
struct SettingsStoreTests {
    @Test("registers every non-nil default in one operation")
    func registersDefaultsAtomically() {
        let storage = DictionarySettingsStorage()
        let store = SettingsStore(storage: storage)

        #expect(storage.registrationCount == 1)
        #expect(storage.lastRegisteredDefaults.count == SettingsKeys.registeredDefaults.count)
        #expect(store[.displayTarget] == .automatic)
        #expect(store[.launchAtLogin] == false)
        #expect(store[.appearance] == SettingsAppearance.auto)
        #expect(store[.reducedMotionOverride] == nil)
        #expect(store[.showMusic])
        #expect(store[.showTimer])
        #expect(store[.showScreenRecording])
        #expect(store[.showAudioRecording])
        #expect(store[.showCharging])
        #expect(store[.enableClaudeCode] == false)
        #expect(store[.enableCodex] == false)
        #expect(store[.enableOpenCode] == false)
        #expect(store[.showAITaskStarted])
        #expect(store[.showAITaskCompleted])
        #expect(store[.showAITaskError])
        #expect(store[.showAINeedsInput])
        #expect(store[.showAIToolActivity] == false)
        #expect(store[.languageOverride] == nil)
        #expect(store[.hasCompletedOnboarding] == false)
    }

    @Test("round-trips every documented setting through its typed key")
    func roundTripsEverySetting() {
        let store = SettingsStore(storage: DictionarySettingsStorage())

        store[.displayTarget] = .named("Studio Display")
        store[.launchAtLogin] = true
        store[.appearance] = SettingsAppearance.dark
        store[.reducedMotionOverride] = true
        store[.showMusic] = false
        store[.showTimer] = false
        store[.showScreenRecording] = false
        store[.showAudioRecording] = false
        store[.showCharging] = false
        store[.enableClaudeCode] = true
        store[.enableCodex] = true
        store[.enableOpenCode] = true
        store[.showAITaskStarted] = false
        store[.showAITaskCompleted] = false
        store[.showAITaskError] = false
        store[.showAINeedsInput] = false
        store[.showAIToolActivity] = true
        store[.languageOverride] = "tr"
        store[.hasCompletedOnboarding] = true

        #expect(store[.displayTarget] == .named("Studio Display"))
        #expect(store[.launchAtLogin])
        #expect(store[.appearance] == SettingsAppearance.dark)
        #expect(store[.reducedMotionOverride] == true)
        #expect(store[.showMusic] == false)
        #expect(store[.showTimer] == false)
        #expect(store[.showScreenRecording] == false)
        #expect(store[.showAudioRecording] == false)
        #expect(store[.showCharging] == false)
        #expect(store[.enableClaudeCode])
        #expect(store[.enableCodex])
        #expect(store[.enableOpenCode])
        #expect(store[.showAITaskStarted] == false)
        #expect(store[.showAITaskCompleted] == false)
        #expect(store[.showAITaskError] == false)
        #expect(store[.showAINeedsInput] == false)
        #expect(store[.showAIToolActivity])
        #expect(store[.languageOverride] == "tr")
        #expect(store[.hasCompletedOnboarding])

        store[.displayTarget] = .builtIn
        store[.reducedMotionOverride] = nil
        store[.languageOverride] = nil

        #expect(store[.displayTarget] == .builtIn)
        #expect(store[.reducedMotionOverride] == nil)
        #expect(store[.languageOverride] == nil)
    }

    @Test("reports the changed key and typed value once")
    func propagatesChanges() {
        let store = SettingsStore(storage: DictionarySettingsStorage())
        var changes: [SettingsChange<Bool>] = []
        let observerID = store.observe(.showCharging) { changes.append($0) }

        store[.showCharging] = false
        store[.showCharging] = false

        #expect(changes == [SettingsChange(key: .showCharging, value: false)])
        store.removeObserver(observerID)
        store[.showCharging] = true
        #expect(changes.count == 1)
    }

    @Test("persists AI integration preferences through their existing value seam")
    func roundTripsAIIntegrationPreferences() {
        let store = SettingsStore(storage: DictionarySettingsStorage())
        let preferences = AIIntegrationPreferences(
            enabledAgentIDs: [.claudeCode, .opencode],
            enabledEventClasses: [.taskStarted, .taskError, .toolActivity]
        )

        store.aiIntegrationPreferences = preferences

        #expect(store.aiIntegrationPreferences == preferences)
    }

    @Test("derives provider enablement from the five provider keys")
    func derivesProviderEnablement() {
        let store = SettingsStore(storage: DictionarySettingsStorage())
        store[.showTimer] = false
        store[.showAudioRecording] = false

        #expect(store.enabledProviderIdentifiers == [
            .music, .screenRecording, .charging
        ])
    }

    @Test("propagates provider key changes as provider enablement")
    func propagatesProviderEnablement() {
        let store = SettingsStore(storage: DictionarySettingsStorage())
        var changes: [(ActivityProviderIdentifier, Bool)] = []
        store.observeProviderEnablement { changes.append(($0, $1)) }

        store[.showCharging] = false

        #expect(changes.count == 1)
        #expect(changes.first?.0 == .charging)
        #expect(changes.first?.1 == false)
    }

    @Test("runs ordered migrations after defaults registration")
    func runsMigrationHook() {
        let storage = DictionarySettingsStorage(values: ["legacy.showCharging": false])
        let migration = SettingsMigration { storage in
            guard let value = storage.object(forKey: "legacy.showCharging") as? Bool else {
                return
            }
            storage.set(value, forKey: SettingsKey<Bool>.showCharging.name)
            storage.removeObject(forKey: "legacy.showCharging")
        }

        let store = SettingsStore(storage: storage, migrations: [migration])

        #expect(store[.showCharging] == false)
        #expect(storage.object(forKey: "legacy.showCharging") == nil)
        #expect(storage.registrationCount == 1)
    }

    @Test("falls back to a documented default when stored data has the wrong type")
    func rejectsTypeDrift() {
        let storage = DictionarySettingsStorage(values: [
            SettingsKey<Bool>.showCharging.name: "yes"
        ])

        let store = SettingsStore(storage: storage)

        #expect(store[.showCharging])
    }
}

@MainActor
private final class DictionarySettingsStorage: SettingsStorage {
    private var values: [String: Any]
    private var registeredDefaults: [String: Any] = [:]

    private(set) var registrationCount = 0
    private(set) var lastRegisteredDefaults: [String: Any] = [:]

    init(values: [String: Any] = [:]) {
        self.values = values
    }

    func register(defaults: [String: Any]) {
        registrationCount += 1
        lastRegisteredDefaults = defaults
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
