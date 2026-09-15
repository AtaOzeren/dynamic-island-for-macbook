import Testing

@testable import KerNotchCore

@Suite("Discord integration preferences")
struct DiscordIntegrationPreferencesTests {
    @Test("the integration is off by default")
    func defaultsAreOff() {
        #expect(DiscordIntegrationPreferences.default.isEnabled == false)
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

    @Test("reads the build's Client ID from its Info.plist")
    func readsBuiltInClientID() {
        let info: [String: Any] = [DiscordApplication.clientIDInfoKey: "1549389234912239636"]

        #expect(DiscordApplication.builtInClientID(infoDictionary: info)?.rawValue == "1549389234912239636")
    }

    /// A SwiftPM build has no Info.plist, a fork may clear the setting, and a
    /// project that lost its xcconfig leaves the placeholder unexpanded.
    @Test("a build without a usable Client ID has none")
    func missingBuiltInClientID() {
        let key = DiscordApplication.clientIDInfoKey
        let unusable: [[String: Any]?] = [
            nil,
            [:],
            [key: ""],
            [key: "$(KERNOTCH_DISCORD_CLIENT_ID)"],
            [key: 1_549_389_234_912_239_636],
        ]

        for info in unusable {
            #expect(DiscordApplication.builtInClientID(infoDictionary: info) == nil)
        }
    }

    @Test("the retired user Client ID key is listed for removal")
    func retiresUserClientIDKey() {
        #expect(SettingsKeys.retiredKeyNames.contains("com.kernotch.settings.integrations.discord.clientID"))
        #expect(SettingsKeys.registeredDefaults.keys.contains { SettingsKeys.retiredKeyNames.contains($0) } == false)
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
