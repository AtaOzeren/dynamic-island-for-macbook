import Foundation
import KerNotchCore
import os

/// Where the integration keeps its tokens between launches.
///
/// Asynchronous so a store can do its work away from the main actor.
public protocol DiscordCredentialStoring: Sendable {
    func credentials(for clientID: DiscordClientID) async -> DiscordCredentials?
    func save(_ credentials: DiscordCredentials, for clientID: DiscordClientID) async
    func deleteCredentials(for clientID: DiscordClientID) async
}

/// The production store: one owner-only JSON file per Client ID in KerNotch's
/// Application Support directory.
///
/// A file rather than the Keychain, deliberately. The legacy Keychain trusts
/// the app by its code signature, and an ad-hoc signature changes with every
/// build, so every update asked the user for their login password — several
/// times per launch. The token is worth less than that friction: it carries
/// only the local RPC scopes for KerNotch's own Discord application, and a
/// process able to read a `0600` file in a `0700` directory under the user's
/// home is already running as the user. The directory permission is the
/// protection that matters; the file permission is kept for defence in depth.
public final class FileDiscordCredentialStore: DiscordCredentialStoring {
    private static let ownerOnlyFilePermissions = 0o600
    private static let ownerOnlyDirectoryPermissions = 0o700
    private static let logger = Logger(subsystem: "com.kernotch.KerNotch", category: "discord-credentials")

    private let directory: URL

    public convenience init() {
        self.init(directory: ApplicationDirectories.applicationSupport)
    }

    init(directory: URL) {
        self.directory = directory
    }

    public func credentials(for clientID: DiscordClientID) async -> DiscordCredentials? {
        guard let data = try? Data(contentsOf: fileURL(for: clientID)) else { return nil }
        return try? JSONDecoder().decode(DiscordCredentials.self, from: data)
    }

    public func save(_ credentials: DiscordCredentials, for clientID: DiscordClientID) async {
        let fileManager = FileManager.default
        let url = fileURL(for: clientID)
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: Self.ownerOnlyDirectoryPermissions]
            )
            // Applied even when the directory already existed, since it is the
            // permission that keeps other accounts out.
            try fileManager.setAttributes(
                [.posixPermissions: Self.ownerOnlyDirectoryPermissions],
                ofItemAtPath: directory.path
            )
            try JSONEncoder().encode(credentials).write(to: url, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: Self.ownerOnlyFilePermissions],
                ofItemAtPath: url.path
            )
        } catch {
            Self.logger.error("Saving Discord credentials failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func deleteCredentials(for clientID: DiscordClientID) async {
        do {
            try FileManager.default.removeItem(at: fileURL(for: clientID))
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            Self.logger.error("Deleting Discord credentials failed: \(String(describing: error), privacy: .public)")
        }
    }

    func fileURL(for clientID: DiscordClientID) -> URL {
        directory.appendingPathComponent("discord-credentials-\(clientID.rawValue).json", isDirectory: false)
    }
}
