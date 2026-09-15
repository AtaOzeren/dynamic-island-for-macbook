import Foundation
import KerNotchCore
import Security
import os

/// Where the integration keeps its tokens between launches.
///
/// Asynchronous so the store can do its work away from the main actor: a
/// Keychain call can block on an access prompt for as long as the user takes.
public protocol DiscordCredentialStoring: Sendable {
    func credentials(for clientID: DiscordClientID) async -> DiscordCredentials?
    func save(_ credentials: DiscordCredentials, for clientID: DiscordClientID) async
    func deleteCredentials(for clientID: DiscordClientID) async
}

/// The production store: one generic-password Keychain item per Client ID.
///
/// The Keychain rather than `UserDefaults` because an access token is a
/// credential for the user's Discord account, and a preferences plist is
/// readable by anything running as the user.
///
/// Holds no state, and its methods are nonisolated `async`, so every Keychain
/// call runs on the global executor rather than the main actor.
public final class KeychainDiscordCredentialStore: DiscordCredentialStoring {
    private static let service = "com.kernotch.KerNotch.discord"
    private static let logger = Logger(subsystem: "com.kernotch.KerNotch", category: "discord-credentials")

    public init() {}

    public func credentials(for clientID: DiscordClientID) async -> DiscordCredentials? {
        var query = Self.itemQuery(for: clientID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                Self.logger.error("Reading Discord credentials failed with status \(status, privacy: .public)")
            }
            return nil
        }
        return try? JSONDecoder().decode(DiscordCredentials.self, from: data)
    }

    public func save(_ credentials: DiscordCredentials, for clientID: DiscordClientID) async {
        guard let data = try? JSONEncoder().encode(credentials) else { return }

        let query = Self.itemQuery(for: clientID)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess {
            Self.logger.error("Saving Discord credentials failed with status \(status, privacy: .public)")
        }
    }

    public func deleteCredentials(for clientID: DiscordClientID) async {
        let status = SecItemDelete(Self.itemQuery(for: clientID) as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            Self.logger.error("Deleting Discord credentials failed with status \(status, privacy: .public)")
        }
    }

    private static func itemQuery(for clientID: DiscordClientID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: clientID.rawValue,
        ]
    }
}
