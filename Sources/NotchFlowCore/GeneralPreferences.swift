/// The user's General-pane choices, as one value the settings window binds to.
///
/// This is the counterpart to `AIIntegrationPreferences`: the pane owns no
/// state, it edits this value, and the composition root writes the value back
/// through the store. Grouping the four rows into one value is what lets the
/// pane's write-through be tested without a `UserDefaults` domain, and what
/// keeps the display target and the appearance from being observed through two
/// separate paths that can report different generations of the same edit.
public struct GeneralPreferences: Equatable, Sendable {
    /// The documented first-launch state from the settings table in
    /// `docs/08-settings-and-localization.md`.
    public static let `default` = GeneralPreferences()

    public var displayTarget: DisplayPreference
    public var launchAtLogin: Bool
    public var appearance: SettingsAppearance

    /// `nil` means follow the system, which is why this is an optional rather
    /// than a `Bool` with a separate "is overridden" flag: two fields would let
    /// the pane express a state — overridden but with no value — that the
    /// setting does not have.
    public var reducedMotionOverride: Bool?

    public init(
        displayTarget: DisplayPreference = .automatic,
        launchAtLogin: Bool = false,
        appearance: SettingsAppearance = .auto,
        reducedMotionOverride: Bool? = nil
    ) {
        self.displayTarget = displayTarget
        self.launchAtLogin = launchAtLogin
        self.appearance = appearance
        self.reducedMotionOverride = reducedMotionOverride
    }
}

public extension SettingsAppearance {
    /// What the General pane calls this choice, kept beside the enum for the
    /// same reason `AIEventClass.displayName` is: the pane never invents a label
    /// a future case would silently miss.
    var displayName: String {
        switch self {
        case .auto: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// The three states the reduced-motion control can be in, as a `CaseIterable`
/// type a picker can enumerate.
///
/// `DisplayPreference` and `Bool?` are not `CaseIterable`, and a picker over a
/// hand-written list of tags is exactly the second list that drifts. This enum
/// is that list, expressed once, with the mapping to and from the stored
/// optional beside it.
public enum ReducedMotionSetting: String, CaseIterable, Equatable, Sendable {
    case followSystem
    case alwaysReduce
    case neverReduce

    public init(override: Bool?) {
        switch override {
        case nil: self = .followSystem
        case true?: self = .alwaysReduce
        case false?: self = .neverReduce
        }
    }

    public var override: Bool? {
        switch self {
        case .followSystem: nil
        case .alwaysReduce: true
        case .neverReduce: false
        }
    }

    public var displayName: String {
        switch self {
        case .followSystem: "Follow system"
        case .alwaysReduce: "Always reduce"
        case .neverReduce: "Never reduce"
        }
    }
}
