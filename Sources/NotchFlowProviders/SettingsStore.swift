import Foundation
import NotchFlowCore

@MainActor
public protocol SettingsStorage: AnyObject {
    func register(defaults registrationDictionary: [String: Any])
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: SettingsStorage {}

public struct SettingsChange<Value: Equatable & Sendable>: Equatable, Sendable {
    public let key: SettingsKey<Value>
    public let value: Value

    public init(key: SettingsKey<Value>, value: Value) {
        self.key = key
        self.value = value
    }
}

@MainActor
public struct SettingsMigration {
    private let migrateStorage: @MainActor (any SettingsStorage) -> Void

    public init(_ migrate: @escaping @MainActor (any SettingsStorage) -> Void) {
        migrateStorage = migrate
    }

    func run(on storage: any SettingsStorage) {
        migrateStorage(storage)
    }
}

@MainActor
public final class SettingsStore {
    public typealias ObserverID = UUID

    private struct Observer {
        let keyName: String
        let notify: (Any) -> Void
    }

    private let storage: any SettingsStorage
    private var observers: [ObserverID: Observer] = [:]

    public init(
        storage: any SettingsStorage = UserDefaults.standard,
        migrations: [SettingsMigration] = []
    ) {
        self.storage = storage
        registerDefaults()
        for migration in migrations {
            migration.run(on: storage)
        }
    }

    public subscript<Value>(key: SettingsKey<Value>) -> Value {
        get {
            key.decode(storage.object(forKey: key.name))
        }
        set {
            let oldValue = self[key]
            if let encodedValue = key.encode(newValue) {
                storage.set(encodedValue, forKey: key.name)
            } else {
                storage.removeObject(forKey: key.name)
            }
            guard oldValue != newValue else { return }
            notifyObservers(of: key, value: newValue)
        }
    }

    @discardableResult
    public func observe<Value>(
        _ key: SettingsKey<Value>,
        observer: @escaping (SettingsChange<Value>) -> Void
    ) -> ObserverID {
        let observerID = ObserverID()
        observers[observerID] = Observer(keyName: key.name) { value in
            guard let typedValue = value as? Value else { return }
            observer(SettingsChange(key: key, value: typedValue))
        }
        return observerID
    }

    public func removeObserver(_ observerID: ObserverID) {
        observers.removeValue(forKey: observerID)
    }

    public var aiIntegrationPreferences: AIIntegrationPreferences {
        get {
            AIIntegrationPreferences(
                enabledAgentIDs: Set(IPCAgentID.allCases.filter(isAgentEnabled)),
                enabledEventClasses: Set(AIEventClass.allCases.filter(isEventClassEnabled))
            )
        }
        set {
            for agentID in IPCAgentID.allCases {
                self[key(for: agentID)] = newValue.isEnabled(agentID)
            }
            for eventClass in AIEventClass.allCases {
                self[key(for: eventClass)] = newValue.isEnabled(eventClass)
            }
        }
    }

    public var generalPreferences: GeneralPreferences {
        get {
            GeneralPreferences(
                displayTarget: self[.displayTarget],
                launchAtLogin: self[.launchAtLogin],
                showMenuBarIcon: self[.showMenuBarIcon],
                appearance: self[.appearance],
                reducedMotionOverride: self[.reducedMotionOverride]
            )
        }
        set {
            self[.displayTarget] = newValue.displayTarget
            self[.launchAtLogin] = newValue.launchAtLogin
            self[.showMenuBarIcon] = newValue.showMenuBarIcon
            self[.appearance] = newValue.appearance
            self[.reducedMotionOverride] = newValue.reducedMotionOverride
        }
    }

    /// Written as a whole set rather than one switch at a time so the pane and
    /// the registry cannot disagree mid-edit: every absent identifier is off,
    /// which is the same rule `enabledProviderIdentifiers` reads back.
    public var enabledProviderIdentifiers: Set<ActivityProviderIdentifier> {
        get {
            Set(ActivityProviderIdentifier.allCases.filter(isProviderEnabled))
        }
        set {
            for identifier in ActivityProviderIdentifier.allCases {
                self[key(for: identifier)] = newValue.contains(identifier)
            }
        }
    }

    public func observeProviderEnablement(
        _ observer: @escaping (ActivityProviderIdentifier, Bool) -> Void
    ) {
        for identifier in ActivityProviderIdentifier.allCases {
            observe(key(for: identifier)) { change in
                observer(identifier, change.value)
            }
        }
    }

    private func registerDefaults() {
        storage.register(defaults: SettingsKeys.registeredDefaults)
    }

    private func isAgentEnabled(_ agentID: IPCAgentID) -> Bool {
        self[key(for: agentID)]
    }

    private func isEventClassEnabled(_ eventClass: AIEventClass) -> Bool {
        self[key(for: eventClass)]
    }

    private func isProviderEnabled(_ identifier: ActivityProviderIdentifier) -> Bool {
        self[key(for: identifier)]
    }

    private func key(for agentID: IPCAgentID) -> SettingsKey<Bool> {
        switch agentID {
        case .claudeCode: .enableClaudeCode
        case .codex: .enableCodex
        case .opencode: .enableOpenCode
        }
    }

    private func key(for eventClass: AIEventClass) -> SettingsKey<Bool> {
        switch eventClass {
        case .taskStarted: .showAITaskStarted
        case .taskCompleted: .showAITaskCompleted
        case .taskError: .showAITaskError
        case .needsInput: .showAINeedsInput
        case .toolActivity: .showAIToolActivity
        }
    }

    private func key(for identifier: ActivityProviderIdentifier) -> SettingsKey<Bool> {
        switch identifier {
        case .music: .showMusic
        case .timer: .showTimer
        case .screenRecording: .showScreenRecording
        case .audioRecording: .showAudioRecording
        case .charging: .showCharging
        }
    }

    private func notifyObservers<Value>(of key: SettingsKey<Value>, value: Value) {
        for observer in observers.values where observer.keyName == key.name {
            observer.notify(value)
        }
    }
}
