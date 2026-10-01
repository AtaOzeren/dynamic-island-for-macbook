import Foundation
import Testing

@testable import KerNotchCore
@testable import KerNotchProviders

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
        #expect(store[.showMenuBarIcon])
        #expect(store[.appearance] == SettingsAppearance.auto)
        #expect(store[.hideInFullScreen] == false)
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
        #expect(store[.showAIAttentionGlow])
        #expect(store[.languageOverride] == nil)
        #expect(store[.hasCompletedOnboarding] == false)
        #expect(store[.cpuWatchdogDisabled] == false)
    }

    /// `store[key]` falls back to the key's own `defaultValue`, so reading
    /// `false` back stays green even if the key is never registered. Only the
    /// registered dictionary proves registration.
    @Test("registers a false default for the hidden cpuWatchdogDisabled key")
    func registersCPUWatchdogKillSwitchDefault() throws {
        let storage = DictionarySettingsStorage()
        _ = SettingsStore(storage: storage)
        let key = SettingsKey<Bool>.cpuWatchdogDisabled

        let registered = try #require(
            storage.lastRegisteredDefaults[key.name] as? Bool
        )
        #expect(registered == false)
    }

    @Test("round-trips every documented setting through its typed key")
    func roundTripsEverySetting() {
        let store = SettingsStore(storage: DictionarySettingsStorage())

        store[.displayTarget] = .named("Studio Display")
        store[.launchAtLogin] = true
        store[.showMenuBarIcon] = false
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
        store[.showAIAttentionGlow] = false
        store[.languageOverride] = "tr"
        store[.hasCompletedOnboarding] = true
        store[.cpuWatchdogDisabled] = true

        #expect(store[.displayTarget] == .named("Studio Display"))
        #expect(store[.launchAtLogin])
        #expect(store[.showMenuBarIcon] == false)
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
        #expect(store[.showAIAttentionGlow] == false)
        #expect(store[.languageOverride] == "tr")
        #expect(store[.hasCompletedOnboarding])
        #expect(store[.cpuWatchdogDisabled])

        store[.displayTarget] = .builtIn
        store[.reducedMotionOverride] = nil
        store[.languageOverride] = nil

        #expect(store[.displayTarget] == .builtIn)
        #expect(store[.reducedMotionOverride] == nil)
        #expect(store[.languageOverride] == nil)
    }

    @Test("round-trips stable display identity even when it contains separators")
    func roundTripsStableDisplayIdentity() {
        let store = SettingsStore(storage: DictionarySettingsStorage())
        let preference = DisplayPreference.identified(
            id: "Studio Display:1920:0",
            name: "Studio Display"
        )

        store[.displayTarget] = preference

        #expect(store[.displayTarget] == preference)
    }

    @Test("round-trips the all-displays target")
    func roundTripsAllDisplays() {
        let store = SettingsStore(storage: DictionarySettingsStorage())

        store[.displayTarget] = .allDisplays

        #expect(store[.displayTarget] == .allDisplays)
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
            enabledEventClasses: [.taskStarted, .taskError, .toolActivity],
            showsAttentionGlow: false
        )

        store.aiIntegrationPreferences = preferences

        #expect(store.aiIntegrationPreferences == preferences)
    }

    @Test("persists Discord integration preferences")
    func roundTripsDiscordIntegrationPreferences() {
        let store = SettingsStore(storage: DictionarySettingsStorage())

        #expect(store.discordIntegrationPreferences == .default)

        store.discordIntegrationPreferences = DiscordIntegrationPreferences(isEnabled: true)
        #expect(store.discordIntegrationPreferences.isEnabled)
        #expect(store[.enableDiscord])
    }

    /// The pet is opt-in: a store nobody has written to must not put a moving
    /// picture on an island the user expects to sit still.
    @Test("persists the pet switch, off until the user turns it on")
    func roundTripsPetPreferences() throws {
        let storage = DictionarySettingsStorage()
        let store = SettingsStore(storage: storage)

        #expect(store.petPreferences == .default)
        #expect(store.petPreferences.isEnabled == false)
        #expect(try #require(storage.lastRegisteredDefaults[SettingsKey<Bool>.showIslandPet.name] as? Bool) == false)

        store.petPreferences = PetPreferences(isEnabled: true)

        #expect(store.petPreferences.isEnabled)
        #expect(store[.showIslandPet])
        #expect(SettingsKey<Bool>.showIslandPet.name == "com.kernotch.settings.pet.enabled")
    }

    @Test("persists which pet lives on the island, the Shiba until another is picked")
    func roundTripsPetSpecies() throws {
        let storage = DictionarySettingsStorage()
        let store = SettingsStore(storage: storage)

        #expect(store.petPreferences.species == .dog)
        #expect(
            try #require(storage.lastRegisteredDefaults[SettingsKey<PetSpecies>.petSpecies.name] as? String) == "dog")

        store.petPreferences = PetPreferences(isEnabled: true, species: .penguin)

        #expect(store.petPreferences == PetPreferences(isEnabled: true, species: .penguin))
        #expect(store[.petSpecies] == .penguin)
        #expect(SettingsKey<PetSpecies>.petSpecies.name == "com.kernotch.settings.pet.species")
    }

    @Test("removes retired keys, and leaves everything else alone")
    func removesRetiredKeys() {
        let storage = DictionarySettingsStorage()
        let retired = "com.kernotch.settings.integrations.discord.clientID"
        storage.set("1549389234912239636", forKey: retired)
        storage.set(true, forKey: SettingsKey<Bool>.enableDiscord.name)

        let store = SettingsStore(storage: storage, migrations: [.removingRetiredKeys])

        #expect(storage.object(forKey: retired) == nil)
        #expect(store[.enableDiscord])
    }

    @Test("persists general preferences through their value seam")
    func roundTripsGeneralPreferences() {
        let store = SettingsStore(storage: DictionarySettingsStorage())
        let preferences = GeneralPreferences(
            displayTarget: .named("Studio Display"),
            launchAtLogin: true,
            showMenuBarIcon: false,
            appearance: .dark,
            islandSize: .large,
            hidesInFullScreen: true,
            reducedMotionOverride: false
        )

        store.generalPreferences = preferences

        #expect(store.generalPreferences == preferences)
        #expect(store[.displayTarget] == .named("Studio Display"))
        #expect(store[.showMenuBarIcon] == false)
        #expect(store[.appearance] == .dark)
        #expect(store[.islandSize] == .large)
        #expect(store[.hideInFullScreen])
    }

    @Test("a store with nothing saved keeps the island over full-screen apps")
    func fullScreenHidingDefaultsOff() {
        let store = SettingsStore(storage: DictionarySettingsStorage())

        #expect(store.generalPreferences.hidesInFullScreen == false)
    }

    @Test("a store with no island size saved opens the minimalist island")
    func islandSizeDefaultsToMinimalist() {
        let store = SettingsStore(storage: DictionarySettingsStorage())

        #expect(store.generalPreferences.islandSize == .minimalist)
    }

    /// A value a future build might write must not leave this one without an
    /// island: an unknown raw value falls back to the default size.
    @Test("an unrecognised stored island size falls back to minimalist")
    func unknownIslandSizeFallsBack() {
        let storage = DictionarySettingsStorage()
        storage.set("enormous", forKey: SettingsKey<IslandSize>.islandSize.name)
        let store = SettingsStore(storage: storage)

        #expect(store.generalPreferences.islandSize == .minimalist)
    }

    /// Clearing the override must remove the key, not store `false` — `false`
    /// means "never reduce", which is a different setting from "follow system".
    @Test("clearing the motion override restores the follow-system default")
    func clearsMotionOverride() {
        let store = SettingsStore(storage: DictionarySettingsStorage())
        store.generalPreferences = GeneralPreferences(reducedMotionOverride: true)

        store.generalPreferences = GeneralPreferences(reducedMotionOverride: nil)

        #expect(store[.reducedMotionOverride] == nil)
    }

    @Test("writing the enabled set switches every provider key")
    func writesProviderEnablementAsASet() {
        let store = SettingsStore(storage: DictionarySettingsStorage())

        store.enabledProviderIdentifiers = [.music, .charging]

        #expect(store.enabledProviderIdentifiers == [.music, .charging])
        #expect(store[.showMusic])
        #expect(!store[.showTimer])
        #expect(!store[.showScreenRecording])
        #expect(!store[.showAudioRecording])
        #expect(store[.showCharging])
    }

    @Test("derives provider enablement from the five provider keys")
    func derivesProviderEnablement() {
        let store = SettingsStore(storage: DictionarySettingsStorage())
        store[.showTimer] = false
        store[.showAudioRecording] = false

        #expect(
            store.enabledProviderIdentifiers == [
                .music, .screenRecording, .charging,
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
