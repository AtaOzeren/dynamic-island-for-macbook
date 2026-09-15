import Testing

@testable import KerNotchCore

@Suite("Discord integration preferences")
struct DiscordIntegrationPreferencesTests {
    @Test("the integration is off and unconfigured by default")
    func defaultsAreOff() {
        #expect(DiscordIntegrationPreferences.default.isEnabled == false)
        #expect(DiscordIntegrationPreferences.default.clientID == nil)
    }

    @Test("accepts an application ID copied with surrounding whitespace")
    func acceptsTrimmedSnowflake() {
        let clientID = DiscordClientID(rawValue: "  1549389234912239636\n")

        #expect(clientID?.rawValue == "1549389234912239636")
    }

    @Test(
        "rejects anything that is not a whole snowflake",
        arguments: [
            "",
            "   ",
            "1234",
            "1549389234912239",
            "1549389234912239636a",
            "-549389234912239636",
            "1549 389234912239636",
            "１５４９３８９２３４９１２２３９６３６",
            "99999999999999999999",
            "123456789012345678901",
        ]
    )
    func rejectsMalformedIDs(rawValue: String) {
        #expect(DiscordClientID(rawValue: rawValue) == nil)
    }

    @Test("accepts the shortest and longest snowflake lengths")
    func acceptsLengthBoundaries() {
        #expect(DiscordClientID(rawValue: "10000000000000000") != nil)
        #expect(DiscordClientID(rawValue: "18446744073709551615") != nil)
    }

    @Test("a stored ID round-trips through its settings key")
    func clientIDKeyRoundTrips() {
        let key = SettingsKey<DiscordClientID?>.discordClientID
        let clientID = DiscordClientID(rawValue: "1549389234912239636")

        #expect(key.decode(key.encode(clientID)) == clientID)
        #expect(key.decode(nil) == nil)
        #expect(key.decode("not an id") == nil)
        #expect(key.encode(nil) == nil)
    }

    @Test("recognises every Discord client and its helper processes")
    func recognisesDiscordProcesses() {
        #expect(DiscordApplication.owns(bundleIdentifier: "com.hnc.Discord"))
        #expect(DiscordApplication.owns(bundleIdentifier: "com.hnc.Discord.helper.Renderer"))
        #expect(DiscordApplication.owns(bundleIdentifier: "com.hnc.DiscordPTB"))
        #expect(DiscordApplication.owns(bundleIdentifier: "com.hnc.DiscordCanary.helper"))
        #expect(DiscordApplication.owns(bundleIdentifier: "com.google.Chrome.helper") == false)
        #expect(DiscordApplication.owns(bundleIdentifier: "") == false)
    }
}
