import Foundation

/// The application ID of KerNotch's Discord application.
///
/// A public identifier, never a secret: authorization uses PKCE, so there is no
/// client secret to store, ship, or ask for. Discord grants the local RPC scopes
/// it is used with only to approved applications — and, before approval, to the
/// application's owner and its listed testers.
public struct DiscordClientID: Hashable, Sendable, RawRepresentable {
    /// A snowflake is an unsigned 64-bit integer. Anything shorter than the
    /// oldest application IDs is a paste that lost digits, not an ID.
    private static let digitCountRange = 17...20

    public let rawValue: String

    /// Accepts the ID with surrounding whitespace, which is how it arrives when
    /// copied out of the Developer Portal.
    public init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            Self.digitCountRange.contains(trimmed.count),
            trimmed.allSatisfy(\.isASCIIDigit),
            UInt64(trimmed) != nil
        else {
            return nil
        }
        self.rawValue = trimmed
    }
}

/// The user's Discord integration choices, as one value the settings pane edits
/// and the composition root applies.
///
/// Which Discord application KerNotch connects through is deliberately not one
/// of them: the connection is KerNotch's, configured per build, so the prompt
/// the user approves always names the application Discord reviewed.
public struct DiscordIntegrationPreferences: Equatable, Sendable {
    public static let `default` = DiscordIntegrationPreferences()

    /// Off by default: turning it on changes what the microphone indicator
    /// reports, which is a choice the user makes rather than one made for them.
    public var isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}

/// The Discord desktop client, as the system names it.
public enum DiscordApplication {
    /// Stable, PTB and Canary, in the order a lookup should prefer them.
    public static let bundleIdentifiers = [
        "com.hnc.Discord",
        "com.hnc.DiscordPTB",
        "com.hnc.DiscordCanary",
    ]

    /// Whether a process belongs to a Discord client.
    ///
    /// Matched by prefix because the microphone is opened by a helper process —
    /// `com.hnc.Discord.helper.Renderer` — not by the application itself, and
    /// PTB and Canary carry the same prefix.
    public static func owns(bundleIdentifier: String) -> Bool {
        bundleIdentifier.hasPrefix(bundleIdentifierPrefix)
    }

    private static let bundleIdentifierPrefix = "com.hnc.Discord"

    /// The `Info.plist` key the build writes KerNotch's Client ID into, from
    /// `KERNOTCH_DISCORD_CLIENT_ID` in `Config/Discord.xcconfig`.
    public static let clientIDInfoKey = "KerNotchDiscordClientID"

    /// The Client ID this build connects with, or `nil` for a build that has
    /// none — a SwiftPM build reads no `Info.plist`, and a fork may clear it. An
    /// unexpanded `$(…)` placeholder is not an ID and reads as none.
    public static func builtInClientID(infoDictionary: [String: Any]?) -> DiscordClientID? {
        (infoDictionary?[clientIDInfoKey] as? String).flatMap(DiscordClientID.init(rawValue:))
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
