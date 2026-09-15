import Foundation
import Testing

@testable import KerNotchProviders

@Suite("Discord IPC frames")
struct DiscordIPCFrameTests {
    private static let handshake = DiscordIPCFrame(opcode: .handshake, payload: Data(#"{"v":1}"#.utf8))

    @Test("encodes a little-endian opcode and length ahead of the payload")
    func encodesHeader() {
        let encoded = Self.handshake.encoded

        #expect(Array(encoded.prefix(8)) == [0, 0, 0, 0, 7, 0, 0, 0])
        #expect(encoded.dropFirst(8) == Data(#"{"v":1}"#.utf8))
    }

    @Test("decodes a frame that arrives in one read")
    func decodesWholeFrame() throws {
        var decoder = DiscordIPCFrameDecoder()

        #expect(try decoder.append(Self.handshake.encoded) == [Self.handshake])
    }

    /// A stream read can end anywhere, including inside the header.
    @Test("reassembles a frame split across reads at every byte")
    func reassemblesSplitFrames() throws {
        let encoded = Self.handshake.encoded

        for split in 1..<encoded.count {
            var decoder = DiscordIPCFrameDecoder()
            #expect(try decoder.append(encoded.prefix(split)).isEmpty)
            #expect(try decoder.append(encoded.dropFirst(split)) == [Self.handshake])
        }
    }

    @Test("decodes several frames delivered in one read, in order")
    func decodesBatchedFrames() throws {
        let pong = DiscordIPCFrame(opcode: .pong, payload: Data())
        var decoder = DiscordIPCFrameDecoder()

        #expect(try decoder.append(Self.handshake.encoded + pong.encoded) == [Self.handshake, pong])
    }

    @Test("rejects an opcode the protocol does not define")
    func rejectsUnknownOpcode() {
        var decoder = DiscordIPCFrameDecoder()
        let bytes = Data([9, 0, 0, 0, 0, 0, 0, 0])

        #expect(throws: DiscordIPCFrameError.unknownOpcode(9)) {
            try decoder.append(bytes)
        }
    }

    @Test("refuses a length that would buffer without limit")
    func rejectsOversizedPayload() {
        var decoder = DiscordIPCFrameDecoder()
        let bytes = Data([1, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0x7F])

        #expect(throws: DiscordIPCFrameError.oversizedPayload(0x7FFF_FFFF)) {
            try decoder.append(bytes)
        }
    }
}

@Suite("Discord IPC socket locator")
struct DiscordIPCSocketLocatorTests {
    @Test("tries the runtime directory before the temporary directory, then /tmp")
    func ordersDirectories() {
        let paths = DiscordIPCSocketLocator.candidatePaths(
            environment: ["XDG_RUNTIME_DIR": "/run/user/501", "TMPDIR": "/var/folders/xy/T/"]
        )

        #expect(paths.first == "/run/user/501/discord-ipc-0")
        #expect(paths[10] == "/var/folders/xy/T/discord-ipc-0")
        #expect(paths.last == "/tmp/discord-ipc-9")
        #expect(paths.count == 30)
    }

    @Test("does not try one directory twice under two names")
    func deduplicatesDirectories() {
        let paths = DiscordIPCSocketLocator.candidatePaths(environment: ["TMPDIR": "/tmp/", "TMP": "/tmp"])

        #expect(paths.count == 10)
    }

    @Test("offers only the sockets that exist")
    func filtersMissingSockets() {
        let paths = DiscordIPCSocketLocator.existingSocketPaths(
            environment: ["TMPDIR": "/var/folders/xy/T"],
            fileExists: { $0 == "/var/folders/xy/T/discord-ipc-1" }
        )

        #expect(paths == ["/var/folders/xy/T/discord-ipc-1"])
    }
}

@Suite("Discord PKCE and token requests")
struct DiscordOAuthTests {
    /// The worked example from RFC 7636, appendix B.
    @Test("derives the S256 challenge the RFC specifies")
    func derivesChallenge() {
        let pkce = DiscordPKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("generates a fresh verifier within the RFC's alphabet and length")
    func generatesVerifier() {
        let first = DiscordPKCE.generate()
        let second = DiscordPKCE.generate()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

        #expect((43...128).contains(first.verifier.count))
        #expect(first.verifier.unicodeScalars.allSatisfy(allowed.contains))
        #expect(first.verifier != second.verifier)
    }

    @Test("form-encodes fields deterministically and escapes reserved characters")
    func formEncodes() {
        let body = DiscordFormEncoding.encode(["grant_type": "authorization_code", "code": "a+b/c=d&e"])

        #expect(body == "code=a%2Bb%2Fc%3Dd%26e&grant_type=authorization_code")
    }

    @Test("treats a token within the renewal margin as expiring")
    func expiryMargin() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let credentials = DiscordCredentials(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: now.addingTimeInterval(1800)
        )

        #expect(credentials.isExpiring(at: now))
        #expect(credentials.isExpiring(at: now.addingTimeInterval(-7200)) == false)
    }
}

@Suite("Discord RPC client")
@MainActor
struct DiscordRPCClientTests {
    private struct Fixture {
        let client: DiscordRPCClient
        let transport: FakeDiscordIPCTransport
    }

    private static func connectedFixture(
        onEvent: @escaping @MainActor (DiscordRPCClientEvent) -> Void = { _ in }
    ) -> Fixture {
        let transport = FakeDiscordIPCTransport()
        let client = DiscordRPCClient(transport: transport)
        client.connect(socketPath: "/tmp/discord-ipc-0", clientID: .testApplication, onEvent: onEvent)
        return Fixture(client: client, transport: transport)
    }

    @Test("sends the handshake with its Client ID once the socket opens")
    func sendsHandshake() throws {
        let fixture = Self.connectedFixture()
        let handshake = try #require(fixture.transport.sentFrames.first)
        let object = try JSONSerialization.jsonObject(with: handshake.payload) as? [String: Any]

        #expect(handshake.opcode == .handshake)
        #expect(object?["v"] as? Int == 1)
        #expect(object?["client_id"] as? String == "1549389234912239636")
    }

    @Test("reports ready with the signed-in user's name")
    func reportsReady() {
        var usernames: [String?] = []
        _ = Self.connectedFixture { event in
            if case .ready(let username) = event { usernames.append(username) }
        }

        #expect(usernames == ["webh0sta"])
    }

    @Test("answers a ping with a pong carrying the same payload")
    func answersPing() {
        let fixture = Self.connectedFixture()

        fixture.transport.sendPing()

        #expect(fixture.transport.sentFrames.last == DiscordIPCFrame(opcode: .pong, payload: Data("{}".utf8)))
    }

    @Test("returns the reply to the command that asked, decoded")
    func correlatesReplies() async throws {
        let fixture = Self.connectedFixture()
        fixture.transport.respond = { sent in
            sent.command == "GET_GUILD" ? .data(["id": "1", "name": sent.arguments["guild_id"] as Any]) : .data(nil)
        }

        let guild = try await fixture.client.request(
            .getGuild,
            arguments: DiscordGuildArguments(guildID: "Ocean View Hotel"),
            returning: DiscordGuildBody.self
        )

        #expect(guild.name == "Ocean View Hotel")
    }

    @Test("throws Discord's error for a command it refused")
    func throwsCommandErrors() async {
        let fixture = Self.connectedFixture()
        fixture.transport.respond = { _ in .error(code: 4006, message: "Not authenticated") }

        await #expect(throws: DiscordRPCError(code: 4006, message: "Not authenticated")) {
            try await fixture.client.perform(.getVoiceSettings)
        }
    }

    @Test("sends leave as an explicit null channel")
    func encodesLeaveAsNull() async throws {
        let fixture = Self.connectedFixture()

        try await fixture.client.perform(.selectVoiceChannel, arguments: DiscordLeaveVoiceChannelArguments())

        let arguments = try #require(fixture.transport.commands(named: "SELECT_VOICE_CHANNEL").first?.arguments)
        #expect(arguments.keys.contains("channel_id"))
        #expect(arguments["channel_id"] is NSNull)
    }

    @Test("hands subscribed events on with their payload")
    func forwardsDispatches() {
        var events: [DiscordRPCEvent] = []
        let fixture = Self.connectedFixture { event in
            if case .dispatch(let name, _) = event { events.append(name) }
        }

        fixture.transport.dispatch("VOICE_SETTINGS_UPDATE", data: ["mute": true])
        fixture.transport.dispatch("SPEAKING_START", data: ["user_id": "1"])

        #expect(events == [.voiceSettingsUpdate])
    }

    @Test("reports Discord's reason when it closes the connection")
    func reportsCloseReason() {
        var reasons: [DiscordRPCError?] = []
        let fixture = Self.connectedFixture { event in
            if case .closed(let reason) = event { reasons.append(reason) }
        }

        fixture.transport.closeFromDiscord(code: 4000, message: "Invalid Client ID")

        #expect(reasons == [DiscordRPCError(code: 4000, message: "Invalid Client ID")])
    }

    /// A command waiting on an authorization prompt must not hang forever when
    /// Discord quits underneath it.
    @Test("fails a pending command when the connection drops")
    func failsPendingCommandsOnClose() async {
        let fixture = Self.connectedFixture()
        fixture.transport.respond = { _ in .silence }

        let pending = Task { try await fixture.client.perform(.authorize) }
        await settleDiscordTasks()
        fixture.transport.dropConnection()

        await #expect(throws: DiscordRPCClient.connectionClosed) {
            try await pending.value
        }
    }

    @Test("refuses to send once disconnected")
    func refusesAfterDisconnect() async {
        let fixture = Self.connectedFixture()

        fixture.client.disconnect()

        await #expect(throws: DiscordRPCClient.connectionClosed) {
            try await fixture.client.perform(.getVoiceSettings)
        }
        #expect(fixture.transport.isOpen == false)
    }
}
