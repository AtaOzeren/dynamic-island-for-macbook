import Testing

@testable import KerNotchCore

/// The Discord call's value semantics: one identity across channel moves, a
/// place among the capture indicators, and a leave action only when there is a
/// channel the RPC connection can leave.
@Suite("DiscordCallActivity")
struct DiscordCallActivityTests {
    private static let lobby = DiscordVoiceChannel(name: "Lobby", serverName: "Ocean View Hotel")

    @Test("keeps one identity while the call moves between channels")
    func identityIsStableAcrossChannels() {
        let first = DiscordCallActivity(channel: Self.lobby, isMuted: false)
        let moved = DiscordCallActivity(
            channel: DiscordVoiceChannel(name: "Room 102", serverName: "Ocean View Hotel"),
            isMuted: true
        )

        #expect(first.identity == moved.identity)
        #expect(first != moved)
    }

    @Test("never shares an identity with the microphone indicator it stands in for")
    func identityDiffersFromMicrophoneRecording() {
        let call = DiscordCallActivity(channel: nil, isMuted: nil)

        #expect(call.identity != RecordingActivity.identity(for: .audio))
        #expect(call.kind == .discordCall)
    }

    @Test("pins beside the capture indicators at high priority")
    func ordersLikeACapture() {
        let call = DiscordCallActivity(channel: nil, isMuted: nil)

        #expect(call.orderBand == .pinned)
        #expect(call.priority == .high)
        #expect(call.autoDismiss == nil)
    }

    @Test("offers to leave the channel it knows")
    func offersLeaveWithAChannel() {
        let call = DiscordCallActivity(channel: Self.lobby, isMuted: false)

        #expect(call.primaryAction?.intent == .leaveDiscordVoiceChannel)
    }

    /// Without the RPC connection there is no channel to name and no way to
    /// leave one, so the affordance is absent rather than inert.
    @Test("offers nothing when only the microphone reported the call")
    func offersNothingWithoutAChannel() {
        let call = DiscordCallActivity(channel: nil, isMuted: nil)

        #expect(call.primaryAction == nil)
    }
}
