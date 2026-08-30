public struct DisplayDescription: Equatable, Sendable {
    public let name: String
    public let isBuiltIn: Bool

    public init(name: String, isBuiltIn: Bool) {
        self.name = name
        self.isBuiltIn = isBuiltIn
    }
}

public enum DisplayPreference: Equatable, Hashable, Sendable {
    case automatic
    case builtIn
    case named(String)
}

public func selectDisplay(
    from availableDisplays: [DisplayDescription],
    preference: DisplayPreference
) -> DisplayDescription? {
    guard let fallbackDisplay = availableDisplays.first(where: \.isBuiltIn)
        ?? availableDisplays.first
    else {
        return nil
    }

    switch preference {
    case .automatic, .builtIn:
        return fallbackDisplay
    case let .named(name):
        return availableDisplays.first { $0.name == name } ?? fallbackDisplay
    }
}
