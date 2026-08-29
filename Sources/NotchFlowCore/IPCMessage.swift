import Foundation

public enum IPCAgentID: String, Codable, CaseIterable, Equatable, Sendable {
    case claudeCode = "claude-code"
    case codex
    case opencode

    /// What the island calls the agent — the short form the state table in
    /// `docs/07-ai-integration.md` uses ("Claude", not "claude-code").
    ///
    /// Separate from `rawValue` on purpose: the raw values are the wire
    /// contract's `agentId` enum and cannot be reworded for display without
    /// breaking every installed hook script.
    public var displayName: String {
        switch self {
        case .claudeCode: "Claude"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        }
    }
}

public struct IPCMessage: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let agentId: IPCAgentID
    public let sessionId: UUID
    public let state: AIAgentState
    public let detail: String
    public let toolName: String?
    public let progress: Double?
    public let timestamp: Date

}

public enum IPCMessageValidationError: Error, Equatable, Sendable {
    case malformedPayload
    case oversizedPayload(maximumByteCount: Int)
    case missingRequiredField(String)
    case unexpectedField(String)
    case unsupportedSchemaVersion(String)
    case disallowedAgentId(String)
    case invalidSessionId(String)
    case unsupportedState(String)
    case stringTooLong(field: String, maximumCharacterCount: Int)
    case unsafeString(field: String)
    case invalidProgress(Double)
    case invalidTimestamp(String)
}

public struct IPCMessageValidator: Sendable {
    public static let maximumPayloadByteCount = 16_384
    public static let maximumDisplayTextCharacterCount = 280
    public static let supportedSchemaVersion = "1.0"

    private static let requiredFields = [
        "schemaVersion",
        "agentId",
        "sessionId",
        "state",
        "detail",
        "timestamp"
    ]
    private static let allowedFields = Set(requiredFields + ["toolName", "progress"])
    private static let shellMetacharacters = CharacterSet(
        charactersIn: "`$&;|<>\\\"'()*?[]{}!~#"
    )

    public init() {}

    public func decode(_ payload: Data) throws -> IPCMessage {
        guard payload.count <= Self.maximumPayloadByteCount else {
            throw IPCMessageValidationError.oversizedPayload(
                maximumByteCount: Self.maximumPayloadByteCount
            )
        }

        let fields = try parseFields(from: payload)
        try validateFieldNames(fields)

        let rawMessage: RawIPCMessage
        do {
            rawMessage = try JSONDecoder().decode(RawIPCMessage.self, from: payload)
        } catch {
            throw IPCMessageValidationError.malformedPayload
        }

        return try validate(rawMessage)
    }

    private func parseFields(from payload: Data) throws -> [String: Any] {
        guard String(data: payload, encoding: .utf8) != nil else {
            throw IPCMessageValidationError.malformedPayload
        }

        do {
            guard let fields = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                throw IPCMessageValidationError.malformedPayload
            }
            return fields
        } catch let error as IPCMessageValidationError {
            throw error
        } catch {
            throw IPCMessageValidationError.malformedPayload
        }
    }

    private func validateFieldNames(_ fields: [String: Any]) throws {
        for requiredField in Self.requiredFields where fields[requiredField] == nil {
            throw IPCMessageValidationError.missingRequiredField(requiredField)
        }

        if let unexpectedField = fields.keys
            .filter({ !Self.allowedFields.contains($0) })
            .sorted()
            .first {
            throw IPCMessageValidationError.unexpectedField(unexpectedField)
        }
    }

    private func validate(_ rawMessage: RawIPCMessage) throws -> IPCMessage {
        guard rawMessage.schemaVersion == Self.supportedSchemaVersion else {
            throw IPCMessageValidationError.unsupportedSchemaVersion(rawMessage.schemaVersion)
        }
        guard let agentId = IPCAgentID(rawValue: rawMessage.agentId) else {
            throw IPCMessageValidationError.disallowedAgentId(rawMessage.agentId)
        }
        guard let sessionId = UUID(uuidString: rawMessage.sessionId) else {
            throw IPCMessageValidationError.invalidSessionId(rawMessage.sessionId)
        }
        guard let state = AIAgentState(rawValue: rawMessage.state) else {
            throw IPCMessageValidationError.unsupportedState(rawMessage.state)
        }

        try validateDisplayText(rawMessage.detail, field: "detail")
        if let toolName = rawMessage.toolName {
            try validateDisplayText(toolName, field: "toolName")
        }
        if let progress = rawMessage.progress, !(0 ... 1).contains(progress) {
            throw IPCMessageValidationError.invalidProgress(progress)
        }
        guard let timestamp = parseTimestamp(rawMessage.timestamp) else {
            throw IPCMessageValidationError.invalidTimestamp(rawMessage.timestamp)
        }

        return IPCMessage(
            schemaVersion: rawMessage.schemaVersion,
            agentId: agentId,
            sessionId: sessionId,
            state: state,
            detail: rawMessage.detail,
            toolName: rawMessage.toolName,
            progress: rawMessage.progress,
            timestamp: timestamp
        )
    }

    private func validateDisplayText(_ value: String, field: String) throws {
        guard value.count <= Self.maximumDisplayTextCharacterCount else {
            throw IPCMessageValidationError.stringTooLong(
                field: field,
                maximumCharacterCount: Self.maximumDisplayTextCharacterCount
            )
        }
        guard value.unicodeScalars.allSatisfy({
            !CharacterSet.controlCharacters.contains($0)
                && !Self.shellMetacharacters.contains($0)
        }) else {
            throw IPCMessageValidationError.unsafeString(field: field)
        }
    }

    private func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct RawIPCMessage: Decodable {
    let schemaVersion: String
    let agentId: String
    let sessionId: String
    let state: String
    let detail: String
    let toolName: String?
    let progress: Double?
    let timestamp: String
}
