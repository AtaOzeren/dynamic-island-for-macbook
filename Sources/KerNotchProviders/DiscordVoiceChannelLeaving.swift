/// What the island's "Leave channel" press needs from the Discord integration,
/// and nothing more.
///
/// A protocol so the presenter routes a press without owning an RPC connection,
/// and so the routing is testable against a fake.
@MainActor
public protocol DiscordVoiceChannelLeaving: AnyObject {
    func leaveVoiceChannel()
}
