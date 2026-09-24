import Foundation

/// The commands KerNotch sends over Discord's RPC protocol. Deliberately a
/// short list: every subscription here is one Discord will wake KerNotch for.
enum DiscordRPCCommand: String, Sendable {
    case authorize = "AUTHORIZE"
    case authenticate = "AUTHENTICATE"
    case getSelectedVoiceChannel = "GET_SELECTED_VOICE_CHANNEL"
    case getChannel = "GET_CHANNEL"
    case getGuild = "GET_GUILD"
    case getVoiceSettings = "GET_VOICE_SETTINGS"
    case selectVoiceChannel = "SELECT_VOICE_CHANNEL"
    case subscribe = "SUBSCRIBE"
    case dispatch = "DISPATCH"
}

/// The events KerNotch subscribes to.
///
/// `VOICE_CONNECTION_STATUS` and `SPEAKING_START`/`STOP` are left out on
/// purpose: the first re-sends its ping statistics every few seconds for the
/// whole call and the second fires on every syllable, and nothing the island
/// shows needs either.
enum DiscordRPCEvent: String, Sendable {
    case ready = "READY"
    case error = "ERROR"
    case voiceChannelSelect = "VOICE_CHANNEL_SELECT"
    case voiceSettingsUpdate = "VOICE_SETTINGS_UPDATE"
}

/// The outer shape of every incoming message; the payload is decoded again by
/// whoever knows what `cmd` and `evt` say it is.
struct DiscordRPCEnvelope: Decodable, Sendable {
    let cmd: String?
    let evt: String?
    let nonce: String?
}

struct DiscordRPCPayload<Body: Decodable>: Decodable {
    let data: Body
}

struct DiscordRPCErrorBody: Decodable, Equatable, Sendable {
    let code: Int
    let message: String
}

/// A command Discord answered with an error, or a connection Discord closed.
struct DiscordRPCError: Error, Equatable, Sendable {
    /// The Client ID in the handshake names no application.
    static let invalidClientIDCode = 4000
    /// The access token was revoked, or expired.
    static let invalidTokenCode = 4009
    /// The OAuth2 flow failed — including the user pressing Cancel.
    static let oauth2ErrorCode = 5000

    let code: Int
    let message: String
}

struct DiscordReadyBody: Decodable, Sendable {
    struct User: Decodable, Sendable {
        let username: String
    }

    let user: User?
}

struct DiscordAuthorizeBody: Decodable, Sendable {
    let code: String
}

struct DiscordChannelBody: Decodable, Sendable {
    let id: String
    let name: String?
    let guildID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case guildID = "guild_id"
    }
}

struct DiscordGuildBody: Decodable, Sendable {
    let id: String
    let name: String
}

struct DiscordVoiceChannelSelectBody: Decodable, Sendable {
    let channelID: String?

    private enum CodingKeys: String, CodingKey {
        case channelID = "channel_id"
    }
}

struct DiscordAuthorizeArguments: Encodable, Sendable {
    /// `rpc` is what `GET_CHANNEL`, `GET_GUILD` and `SELECT_VOICE_CHANNEL`
    /// require; `rpc.voice.read` covers the selected channel and mute state.
    static let scopes = ["rpc", "rpc.voice.read"]

    let clientID: String
    let scopes: [String]
    let codeChallenge: String
    let codeChallengeMethod = "S256"

    private enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case scopes
        case codeChallenge = "code_challenge"
        case codeChallengeMethod = "code_challenge_method"
    }
}

struct DiscordAuthenticateArguments: Encodable, Sendable {
    let accessToken: String

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

struct DiscordChannelArguments: Encodable, Sendable {
    let channelID: String

    private enum CodingKeys: String, CodingKey {
        case channelID = "channel_id"
    }
}

struct DiscordGuildArguments: Encodable, Sendable {
    let guildID: String

    private enum CodingKeys: String, CodingKey {
        case guildID = "guild_id"
    }
}

/// `SELECT_VOICE_CHANNEL` with an explicit `null`, which is how Discord is told
/// to leave. An omitted key would be a malformed join rather than a leave.
struct DiscordLeaveVoiceChannelArguments: Encodable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case channelID = "channel_id"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .channelID)
    }
}

struct DiscordVoiceSettingsBody: Decodable, Sendable {
    let mute: Bool
    /// Deafened: the user hears nothing, and Discord switches the microphone
    /// off with it. Read separately from `mute`, which Discord leaves alone —
    /// so an island that only watched `mute` drew a live microphone for a user
    /// who could neither speak nor hear.
    let deaf: Bool

    private enum CodingKeys: String, CodingKey {
        case mute
        case deaf
    }

    /// Accepts `1`/`0` as well as `true`/`false`: the flags are documented as
    /// booleans, but a client that serialises them numerically must not read as
    /// "unknown" for the length of a call.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mute = Self.flag(in: container, forKey: .mute)
        deaf = Self.flag(in: container, forKey: .deaf)
    }

    private static func flag(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Bool {
        if let flag = try? container.decode(Bool.self, forKey: key) { return flag }
        if let number = try? container.decode(Int.self, forKey: key) { return number != 0 }
        return false
    }
}
