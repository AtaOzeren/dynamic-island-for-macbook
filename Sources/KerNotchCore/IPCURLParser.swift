import Foundation

public enum IPCURLParserError: Error, Equatable, Sendable {
    case unsupportedScheme
    case unsupportedEndpoint
    case missingPayload
    case undecodablePayload
    case invalidMessage(IPCMessageValidationError)
}

public struct IPCURLParser: Sendable {
    /// Both spellings are accepted because a hook installed before the app was
    /// renamed still opens the old scheme, and the app it reaches is this one.
    private static let acceptedSchemes: Set<String> = [
        HookSnippetGenerator.urlScheme,
        HookSnippetGenerator.legacyURLScheme,
    ]

    public init() {}

    public func parse(_ url: URL) throws -> IPCMessage {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            Self.acceptedSchemes.contains(scheme)
        else {
            throw IPCURLParserError.unsupportedScheme
        }
        guard components.host == "ai-status" else {
            throw IPCURLParserError.unsupportedEndpoint
        }
        guard let payloadItem = components.queryItems?.first(where: { $0.name == "payload" }) else {
            throw IPCURLParserError.missingPayload
        }
        guard let payload = payloadItem.value?.data(using: .utf8) else {
            throw IPCURLParserError.undecodablePayload
        }

        do {
            return try IPCMessageValidator().decode(payload)
        } catch let error as IPCMessageValidationError {
            throw IPCURLParserError.invalidMessage(error)
        }
    }
}
