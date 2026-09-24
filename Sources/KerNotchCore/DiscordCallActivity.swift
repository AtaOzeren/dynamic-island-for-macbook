import Foundation

/// The voice channel a Discord call is connected to, as Discord's local RPC
/// reports it.
public struct DiscordVoiceChannel: Equatable, Sendable {
    public let name: String
    /// `nil` for a direct message or group call, which belongs to no server.
    public let serverName: String?

    public init(name: String, serverName: String?) {
        self.name = name
        self.serverName = serverName
    }
}

/// A Discord voice call in progress.
///
/// Two signals report a call and either one is enough on its own. CoreAudio's
/// per-process input state says Discord holds the microphone — no setup, no
/// network, no permission. Discord's local RPC, once the user has connected it,
/// says which channel the call is in and whether the user is muted. The RPC half
/// is detail rather than presence: without it the call is still shown, it just
/// cannot be named or left.
///
/// A separate activity from `RecordingActivity` rather than an attribution on
/// it, so a call and some other application using the microphone at the same
/// time are two facts on the island instead of one indicator that has to pick.
public struct DiscordCallActivity: Activity, Equatable {
    /// One call at a time: the Discord client joins one voice channel, so moving
    /// between channels updates the element already on screen.
    public static let identity = ActivityIdentity("kernotch.discord.call")

    /// `nil` while the RPC connection is not there to say.
    public let channel: DiscordVoiceChannel?

    /// `nil` while the RPC connection is not there to say. CoreAudio cannot
    /// answer this: Discord keeps its input stream open while muted.
    public let isMuted: Bool?

    /// Deafened: the user hears nothing, and Discord switches the microphone
    /// off with it. Its own fact rather than a kind of mute, because Discord
    /// leaves the mute flag alone when you deafen — so an island reading mute
    /// alone showed a live microphone for someone who could neither speak nor
    /// hear. `nil` while the RPC connection is not there to say.
    public let isDeafened: Bool?

    public init(channel: DiscordVoiceChannel?, isMuted: Bool?, isDeafened: Bool? = nil) {
        self.channel = channel
        self.isMuted = isMuted
        self.isDeafened = isDeafened
    }

    public var identity: ActivityIdentity { Self.identity }

    public var kind: ActivityKind { .discordCall }

    /// A live call holds the microphone, so it pins beside the capture
    /// indicators it stands in for.
    public var orderBand: ActivityOrderBand { .pinned }

    public var priority: ActivityPriority { .high }

    public var compactRank: CompactRank { .call }

    /// Offered only while a channel is known: leaving goes through the same RPC
    /// connection that named the channel, so without one there is nothing a
    /// press could do.
    public var primaryAction: PrimaryAction? {
        guard channel != nil else { return nil }
        return PrimaryAction(
            title: localized("Leave channel"),
            symbolName: "phone.down.fill",
            intent: .leaveDiscordVoiceChannel
        )
    }
}
