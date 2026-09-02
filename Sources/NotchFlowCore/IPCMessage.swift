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
    /// The top-level session this one belongs to, when it is a sub-agent.
    ///
    /// An agent that delegates work spawns a real child session with its own
    /// identifier — OpenCode's `task` tool does this for every sub-agent — and
    /// without this field the island counts each of them as another running
    /// agent. One terminal delegating to four sub-agents then reads as five
    /// concurrent agents, which is both wrong and useless.
    ///
    /// Omitted when the session is itself a top level one, so an agent that has
    /// no notion of sub-sessions sends exactly what it sent before.
    public let rootSessionId: UUID?
    /// What to call this session in the sub-agent list, when it is one.
    ///
    /// The delegated agent's own name — "explore", "general" — because a list of
    /// four rows reading "1", "2", "3", "4" tells the user nothing about which
    /// one stopped to ask a question.
    public let sessionName: String?
    public let workspace: String?
    public let state: AIAgentState
    public let detail: String
    public let toolName: String?
    public let progress: Double?
    public let timestamp: Date

    public init(
        schemaVersion: String,
        agentId: IPCAgentID,
        sessionId: UUID,
        rootSessionId: UUID? = nil,
        sessionName: String? = nil,
        workspace: String? = nil,
        state: AIAgentState,
        detail: String,
        toolName: String? = nil,
        progress: Double? = nil,
        timestamp: Date
    ) {
        self.schemaVersion = schemaVersion
        self.agentId = agentId
        self.sessionId = sessionId
        // A session naming itself as its own parent is a root session written
        // the long way; normalising here means nothing downstream has to treat
        // "child of itself" as a case.
        self.rootSessionId = rootSessionId == sessionId ? nil : rootSessionId
        self.sessionName = sessionName
        self.workspace = workspace
        self.state = state
        self.detail = detail
        self.toolName = toolName
        self.progress = progress
        self.timestamp = timestamp
    }
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
        "timestamp",
    ]
    /// Optional fields a 1.0 envelope may carry.
    ///
    /// `rootSessionId` and `sessionName` were added after 1.0 shipped and are
    /// deliberately not a version bump: the version is checked exactly, so
    /// raising it would reject every hook already installed on a user's machine
    /// until they reinstalled it. An optional field an older island ignores and
    /// an older hook never sends is compatible in both directions, which a
    /// version bump is not.
    private static let allowedFields = Set(
        requiredFields + ["toolName", "progress", "rootSessionId", "sessionName", "workspace"]
    )
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
        guard String(bytes: payload, encoding: .utf8) != nil else {
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
            .first
        {
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
        var rootSessionId: UUID?
        if let rawRootSessionId = rawMessage.rootSessionId {
            guard let parsed = UUID(uuidString: rawRootSessionId) else {
                throw IPCMessageValidationError.invalidSessionId(rawRootSessionId)
            }
            rootSessionId = parsed
        }
        guard let state = AIAgentState(rawValue: rawMessage.state) else {
            throw IPCMessageValidationError.unsupportedState(rawMessage.state)
        }

        try validateDisplayText(rawMessage.detail, field: "detail")
        if let toolName = rawMessage.toolName {
            try validateDisplayText(toolName, field: "toolName")
        }
        if let sessionName = rawMessage.sessionName {
            try validateDisplayText(sessionName, field: "sessionName")
        }
        if let workspace = rawMessage.workspace {
            try validateDisplayText(workspace, field: "workspace")
        }
        if let progress = rawMessage.progress, !(0...1).contains(progress) {
            throw IPCMessageValidationError.invalidProgress(progress)
        }
        guard let timestamp = parseTimestamp(rawMessage.timestamp) else {
            throw IPCMessageValidationError.invalidTimestamp(rawMessage.timestamp)
        }

        return IPCMessage(
            schemaVersion: rawMessage.schemaVersion,
            agentId: agentId,
            sessionId: sessionId,
            rootSessionId: rootSessionId,
            sessionName: rawMessage.sessionName,
            workspace: rawMessage.workspace,
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
        guard
            value.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
                    && !Self.shellMetacharacters.contains($0)
            })
        else {
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
    let rootSessionId: String?
    let sessionName: String?
    let workspace: String?
    let state: String
    let detail: String
    let toolName: String?
    let progress: Double?
    let timestamp: String
}
