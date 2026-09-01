public struct DisplayDescription: Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let isBuiltIn: Bool

    public init(identifier: String? = nil, name: String, isBuiltIn: Bool) {
        self.identifier = identifier ?? name
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}

public enum DisplayPreference: Equatable, Hashable, Sendable {
    case automatic
    case allDisplays
    case builtIn
    case named(String)
    case identified(id: String, name: String)
}

public func selectDisplay(
    from availableDisplays: [DisplayDescription],
    preference: DisplayPreference
) -> DisplayDescription? {
    guard
        let fallbackDisplay = availableDisplays.first(where: \.isBuiltIn)
            ?? availableDisplays.first
    else {
        return nil
    }

    switch preference {
    case .automatic, .allDisplays, .builtIn:
        return fallbackDisplay
    case .named(let name):
        return availableDisplays.first { $0.name == name } ?? fallbackDisplay
    case .identified(let id, _):
        return availableDisplays.first { $0.identifier == id } ?? fallbackDisplay
    }
}

public func selectDisplays(
    from availableDisplays: [DisplayDescription],
    preference: DisplayPreference
) -> [DisplayDescription] {
    guard preference != .allDisplays else { return availableDisplays }
    return selectDisplay(from: availableDisplays, preference: preference).map { [$0] } ?? []
}

public func normalizeDisplayPreference(
    _ preference: DisplayPreference,
    availableDisplayCount: Int
) -> DisplayPreference {
    guard preference == .allDisplays, availableDisplayCount < 2 else { return preference }
    return .automatic
}
