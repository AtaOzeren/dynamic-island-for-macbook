import Foundation
import KerNotchCore
import Testing

@testable import KerNotchProviders

/// The token file against a real, per-test temporary directory: what matters
/// here is exactly what a fake would hide — the permissions on disk.
@Suite("FileDiscordCredentialStore")
struct FileDiscordCredentialStoreTests {
    private static let clientID = DiscordClientID(rawValue: "1549389234912239636")!
    private static let otherClientID = DiscordClientID(rawValue: "1234567890123456789")!
    private static let credentials = DiscordCredentials(
        accessToken: "access",
        refreshToken: "refresh",
        expiresAt: Date(timeIntervalSinceReferenceDate: 1_000_000)
    )

    private static func withStore(_ body: (FileDiscordCredentialStore, URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kernotch-discord-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("KerNotch", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try await body(FileDiscordCredentialStore(directory: directory), directory)
    }

    private static func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.posixPermissions] as? Int)
    }

    @Test("reads back what it saved")
    func roundTrips() async throws {
        try await Self.withStore { store, _ in
            await store.save(Self.credentials, for: Self.clientID)

            #expect(await store.credentials(for: Self.clientID) == Self.credentials)
        }
    }

    @Test("has nothing for an application it never saved")
    func emptyByDefault() async throws {
        try await Self.withStore { store, _ in
            #expect(await store.credentials(for: Self.clientID) == nil)
        }
    }

    @Test("keeps the token readable by the user alone")
    func ownerOnlyPermissions() async throws {
        try await Self.withStore { store, directory in
            await store.save(Self.credentials, for: Self.clientID)

            let directoryPermissions = try Self.permissions(of: directory)
            let filePermissions = try Self.permissions(of: store.fileURL(for: Self.clientID))
            #expect(directoryPermissions == 0o700)
            #expect(filePermissions == 0o600)
        }
    }

    @Test("tightens a directory that already existed with looser permissions")
    func tightensExistingDirectory() async throws {
        try await Self.withStore { store, directory in
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )

            await store.save(Self.credentials, for: Self.clientID)

            let directoryPermissions = try Self.permissions(of: directory)
            #expect(directoryPermissions == 0o700)
        }
    }

    @Test("keeps each application's tokens apart")
    func separatesApplications() async throws {
        try await Self.withStore { store, _ in
            await store.save(Self.credentials, for: Self.clientID)

            #expect(await store.credentials(for: Self.otherClientID) == nil)
        }
    }

    @Test("deletes the token, and deleting one that is gone is not an error")
    func deletes() async throws {
        try await Self.withStore { store, _ in
            await store.save(Self.credentials, for: Self.clientID)

            await store.deleteCredentials(for: Self.clientID)
            await store.deleteCredentials(for: Self.clientID)

            #expect(await store.credentials(for: Self.clientID) == nil)
        }
    }

    @Test("treats an unreadable file as no token rather than failing")
    func ignoresCorruptFile() async throws {
        try await Self.withStore { store, directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: store.fileURL(for: Self.clientID))

            #expect(await store.credentials(for: Self.clientID) == nil)
        }
    }
}
