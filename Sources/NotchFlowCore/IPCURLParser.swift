import Foundation

public enum IPCURLParserError: Error, Equatable, Sendable {
    case unsupportedScheme
    case unsupportedEndpoint
    case missingPayload
    case undecodablePayload
    case invalidMessage(IPCMessageValidationError)
}

public struct IPCURLParser: Sendable {
    public init() {}

    public func parse(_ url: URL) throws -> IPCMessage {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "notchflow"
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
