import Foundation
import NotchFlowCore
import Testing

@testable import NotchFlowProviders

/// Exercises `installationState()` against a real filesystem rather than the
/// in-memory doubles the per-installer suites use.
///
/// The unit suites prove the state machine; these prove the two properties that
/// only a real filesystem can falsify: that the state tracks `install()` and
/// `uninstall()` round-trip, and that asking the question leaves the home
/// directory byte-for-byte and mtime-for-mtime untouched.
@Suite("HookInstallationState QA")
struct HookInstallationStateQATests {
    @Test("state round-trips through install and uninstall for every installer")
    func stateRoundTrip() throws {
        let home = try TemporaryHome()
        defer { home.remove() }

        for installer in Self.installers(home: home.url) {
            #expect(installer.state() == .configurationMissing, "\(installer.name) before install")

            try installer.install()
            #expect(installer.state() == .hookInstalled, "\(installer.name) after install")

            try installer.uninstall()
            #expect(installer.state() != .hookInstalled, "\(installer.name) after uninstall")
        }
    }

    @Test("querying state creates, modifies, and deletes nothing")
    func stateIsReadOnly() throws {
        let home = try TemporaryHome()
        defer { home.remove() }

        for installer in Self.installers(home: home.url) {
            try installer.install()
        }

        let before = try home.snapshot()
        for installer in Self.installers(home: home.url) {
            _ = installer.state()
        }
        let after = try home.snapshot()

        #expect(before == after)
    }

    private static func installers(home: URL) -> [InstallerUnderTest] {
        let claude = ClaudeCodeHookInstaller(homeDirectory: home)
        let codex = CodexHookInstaller(homeDirectory: home)
        let opencode = OpenCodePluginInstaller(homeDirectory: home)
        return [
            InstallerUnderTest(
                name: "ClaudeCodeHookInstaller",
                state: claude.installationState,
                install: claude.install,
                uninstall: claude.uninstall
            ),
            InstallerUnderTest(
                name: "CodexHookInstaller",
                state: codex.installationState,
                install: codex.install,
                uninstall: codex.uninstall
            ),
            InstallerUnderTest(
                name: "OpenCodePluginInstaller",
                state: opencode.installationState,
                install: opencode.install,
                uninstall: opencode.uninstall
            ),
        ]
    }
}

private struct InstallerUnderTest {
    let name: String
    let state: () -> HookInstallationState
    let install: () throws -> Void
    let uninstall: () throws -> Void
}

private struct TemporaryHome {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appending(path: "notchflow-qa-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Every path under the home paired with its size and modification date, so
    /// a creation, a deletion, and an in-place rewrite all show as a difference.
    func snapshot() throws -> [String: String] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard
            let walker = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: keys
            )
        else {
            return [:]
        }

        var entries: [String: String] = [:]
        for case let path as URL in walker {
            let values = try path.resourceValues(forKeys: Set(keys))
            let size = values.fileSize.map(String.init) ?? "-"
            let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            entries[path.path] = "\(size)@\(modified)"
        }
        return entries
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
