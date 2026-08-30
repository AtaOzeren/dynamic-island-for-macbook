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
        name = "com.notchflow.settings.\(path)"
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
                case "builtIn": return .builtIn
                default:
                    let prefix = "named:"
                    guard representation.hasPrefix(prefix) else { return nil }
                    return .named(String(representation.dropFirst(prefix.count)))
                }
            },
            encode: { preference in
                switch preference {
                case .automatic: "automatic"
                case .builtIn: "builtIn"
                case .named(let name): "named:\(name)"
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

extension SettingsKey where Value == Bool {
    public static var launchAtLogin: Self { boolKey(path: "general.launchAtLogin", defaultValue: false) }
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
    public static var hasCompletedOnboarding: Self {
        boolKey(path: "general.hasCompletedOnboarding", defaultValue: false)
    }
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
    public static var registeredDefaults: [String: Any] {
        var defaults: [String: Any] = [:]
        register(.displayTarget, in: &defaults)
        register(.launchAtLogin, in: &defaults)
        register(.appearance, in: &defaults)
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
        register(.hasCompletedOnboarding, in: &defaults)
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
