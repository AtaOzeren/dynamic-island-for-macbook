import Foundation

/// Single resolution point for the user directories KerNotch writes to.
/// `FileManager.urls(for:in:)` can return an empty array in some test
/// configurations, so every caller needs the same home-relative
/// fallback — keeping that fallback in one place stops the copies drifting.
enum ApplicationDirectories {
    static var library: URL {
        FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
    }

    static var logs: URL {
        library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("KerNotch", isDirectory: true)
    }

    static var applicationSupport: URL {
        (FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? library.appendingPathComponent("Application Support", isDirectory: true))
            .appendingPathComponent("KerNotch", isDirectory: true)
    }
}
