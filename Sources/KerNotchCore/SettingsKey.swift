import Foundation

public struct SettingsKey<Value: Equatable & Sendable>: Equatable, Hashable, Sendable {
    public let name: String
    public let defaultValue: Value

    private let decodeValue: @Sendable (Any) -> Value?
    private let encodeValue: @Sendable (Value) -> Any?

    public init(
        path: String,
        defaultValue: Value,
        decode: @escaping @Sendable (Any) -> Value?,
        encode: @escaping @Sendable (Value) -> Any?
    ) {
        name = SettingsKeys.namePrefix + path
        self.defaultValue = defaultValue
        decodeValue = decode
        encodeValue = encode
    }

    public func decode(_ object: Any?) -> Value {
        object.flatMap(decodeValue) ?? defaultValue
    }

    public func encode(_ value: Value) -> Any? {
        encodeValue(value)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

extension SettingsKey where Value == DisplayPreference {
    public static var displayTarget: Self {
        SettingsKey(
            path: "display.target",
            defaultValue: .automatic,
            decode: { object in
                guard let representation = object as? String else { return nil }
                switch representation {
                case "automatic": return .automatic
                case "allDisplays": return .allDisplays
                case "builtIn": return .builtIn
                default:
                    let identifiedPrefix = "identified:"
                    if representation.hasPrefix(identifiedPrefix) {
                        let payload = representation.dropFirst(identifiedPrefix.count)
                        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
                        guard
                            parts.count == 2,
                            let idData = Data(base64Encoded: parts[0]),
                            let nameData = Data(base64Encoded: parts[1])
                        else {
                            return nil
                        }
                        return .identified(
                            id: String(decoding: idData, as: UTF8.self),
                            name: String(decoding: nameData, as: UTF8.self)
                        )
                    }
                    let prefix = "named:"
                    guard representation.hasPrefix(prefix) else { return nil }
                    return .named(String(representation.dropFirst(prefix.count)))
                }
            },
            encode: { preference in
                switch preference {
                case .automatic: "automatic"
                case .allDisplays: "allDisplays"
                case .builtIn: "builtIn"
                case .named(let name): "named:\(name)"
                case .identified(let id, let name):
                    "identified:\(Data(id.utf8).base64EncodedString()):\(Data(name.utf8).base64EncodedString())"
                }
            }
        )
    }
}

extension SettingsKey where Value == SettingsAppearance {
    public static var appearance: Self {
        rawRepresentableKey(
            path: "general.appearance",
            defaultValue: SettingsAppearance.auto
        )
    }
}

extension SettingsKey where Value == IslandSize {
    public static var islandSize: Self {
        rawRepresentableKey(
            path: "general.islandSize",
            defaultValue: IslandSize.minimalist
        )
    }
}

extension SettingsKey where Value == PetSpecies {
    public static var petSpecies: Self {
        rawRepresentableKey(
            path: "pet.species",
            defaultValue: PetSpecies.dog
        )
    }
}

extension SettingsKey where Value == Bool {
    public static var launchAtLogin: Self { boolKey(path: "general.launchAtLogin", defaultValue: false) }
    public static var cpuWatchdogDisabled: Self {
        boolKey(path: "cpuWatchdog.disabled", defaultValue: false)
    }
    public static var showMenuBarIcon: Self {
        boolKey(path: "general.showMenuBarIcon", defaultValue: true)
    }
    public static var showMusic: Self { boolKey(path: "providers.music.enabled", defaultValue: true) }
    public static var showTimer: Self { boolKey(path: "providers.timer.enabled", defaultValue: true) }
    public static var showScreenRecording: Self {
        boolKey(path: "providers.screenRecording.enabled", defaultValue: true)
    }
    public static var showAudioRecording: Self {
        boolKey(path: "providers.audioRecording.enabled", defaultValue: true)
    }
    public static var showCharging: Self { boolKey(path: "providers.charging.enabled", defaultValue: true) }
    public static var enableClaudeCode: Self {
        boolKey(path: "ai.agents.claudeCode.enabled", defaultValue: false)
    }
    public static var enableCodex: Self { boolKey(path: "ai.agents.codex.enabled", defaultValue: false) }
    public static var enableOpenCode: Self {
        boolKey(path: "ai.agents.openCode.enabled", defaultValue: false)
    }
    public static var showAITaskStarted: Self { boolKey(path: "ai.events.taskStarted", defaultValue: true) }
    public static var showAITaskCompleted: Self {
        boolKey(path: "ai.events.taskCompleted", defaultValue: true)
    }
    public static var showAITaskError: Self { boolKey(path: "ai.events.taskError", defaultValue: true) }
    public static var showAINeedsInput: Self { boolKey(path: "ai.events.needsInput", defaultValue: true) }
    public static var showAIToolActivity: Self {
        boolKey(path: "ai.events.toolActivity", defaultValue: false)
    }
    public static var showAIAttentionGlow: Self {
        boolKey(path: "ai.presentation.attentionGlow", defaultValue: true)
    }
    public static var hasCompletedOnboarding: Self {
        boolKey(path: "general.hasCompletedOnboarding", defaultValue: false)
    }
    public static var enableDiscord: Self {
        boolKey(path: "integrations.discord.enabled", defaultValue: false)
    }
    public static var showIslandPet: Self { boolKey(path: "pet.enabled", defaultValue: false) }
}

extension SettingsKey where Value == Bool? {
    public static var reducedMotionOverride: Self {
        SettingsKey(
            path: "general.reducedMotionOverride",
            defaultValue: nil,
            decode: { $0 as? Bool },
            encode: { $0 }
        )
    }
}

extension SettingsKey where Value == String? {
    public static var languageOverride: Self {
        SettingsKey(
            path: "general.languageOverride",
            defaultValue: nil,
            decode: { $0 as? String },
            encode: { $0 }
        )
    }
}

public enum SettingsKeys {
    /// What every setting's stored name begins with, so KerNotch's settings can
    /// be told apart from anything else in a shared store.
    public static let namePrefix = "com.kernotch.settings."

    /// Keys a released build no longer reads, removed by migration so they do
    /// not linger in the user's preferences.
    public static let retiredKeyNames = [
        // A Client ID the user typed in; the connection now uses the build's own.
        "com.kernotch.settings.integrations.discord.clientID"
    ]

    public static var registeredDefaults: [String: Any] {
        var defaults: [String: Any] = [:]
        register(.displayTarget, in: &defaults)
        register(.launchAtLogin, in: &defaults)
        register(.showMenuBarIcon, in: &defaults)
        register(.appearance, in: &defaults)
        register(.islandSize, in: &defaults)
        register(.showMusic, in: &defaults)
        register(.showTimer, in: &defaults)
        register(.showScreenRecording, in: &defaults)
        register(.showAudioRecording, in: &defaults)
        register(.showCharging, in: &defaults)
        register(.enableClaudeCode, in: &defaults)
        register(.enableCodex, in: &defaults)
        register(.enableOpenCode, in: &defaults)
        register(.showAITaskStarted, in: &defaults)
        register(.showAITaskCompleted, in: &defaults)
        register(.showAITaskError, in: &defaults)
        register(.showAINeedsInput, in: &defaults)
        register(.showAIToolActivity, in: &defaults)
        register(.showAIAttentionGlow, in: &defaults)
        register(.hasCompletedOnboarding, in: &defaults)
        register(.cpuWatchdogDisabled, in: &defaults)
        register(.enableDiscord, in: &defaults)
        register(.showIslandPet, in: &defaults)
        register(.petSpecies, in: &defaults)
        return defaults
    }

    private static func register<Value>(
        _ key: SettingsKey<Value>,
        in defaults: inout [String: Any]
    ) {
        if let value = key.encode(key.defaultValue) {
            defaults[key.name] = value
        }
    }
}

private func boolKey(path: String, defaultValue: Bool) -> SettingsKey<Bool> {
    SettingsKey(path: path, defaultValue: defaultValue, decode: { $0 as? Bool }, encode: { $0 })
}

private func rawRepresentableKey<Value>(
    path: String,
    defaultValue: Value
) -> SettingsKey<Value> where Value: RawRepresentable & Equatable & Sendable, Value.RawValue == String {
    SettingsKey(
        path: path,
        defaultValue: defaultValue,
        decode: { ($0 as? String).flatMap(Value.init(rawValue:)) },
        encode: { $0.rawValue }
    )
}
