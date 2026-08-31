import Foundation
import Testing

@testable import NotchFlowUI

/// Todo 63's acceptance criterion, checked the only way that is honest in a
/// SwiftPM test: by compiling the catalogs the way Xcode does and resolving
/// against the result.
///
/// SwiftPM copies `.xcstrings` into the bundle without compiling it, so
/// `String(localized:bundle: .module)` under `swift test` serves the English
/// fallback whatever locale it is handed — a test asserting on `.module` would
/// pass just as happily with every Turkish entry deleted. Running
/// `xcstringstool compile` produces the `tr.lproj` an app build produces, which
/// makes "Turkish resolves end to end" a claim about the shipped artefact
/// rather than about the source file.
@Suite("Turkish localization")
struct TurkishLocalizationTests {
    @Test(
        "every catalog resolves Turkish rather than falling back to English",
        arguments: [
            ("Sources/NotchFlowCore/Resources/Localizable.xcstrings", "Charging", "Şarj oluyor"),
            ("Sources/NotchFlowUI/Resources/Localizable.xcstrings", "Skip", "Atla"),
            ("NotchFlow/Localizable.xcstrings", "Welcome to NotchFlow", "NotchFlow'a hoş geldiniz"),
        ]
    )
    func turkishResolvesFromEveryCatalog(catalog: String, key: String, turkish: String) throws {
        try withTurkishBundle(for: catalog) { bundle in
            #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == turkish)
        }
    }

    /// Turkish is a one/other language in CLDR, but its numeral phrases take the
    /// singular noun — "3 etkinlik", never "3 etkinlikler". Both forms therefore
    /// carry the same text, which is a translation decision rather than a
    /// copy-paste, and only formatting an actual count tells the two apart.
    @Test("the plural entry formats a count in Turkish")
    func pluralFormatsInTurkish() throws {
        try withTurkishBundle(for: "Sources/NotchFlowUI/Resources/Localizable.xcstrings") { bundle in
            let format = bundle.localizedString(forKey: "%lld more activities", value: nil, table: nil)

            #expect(String(format: format, 1) == "1 etkinlik daha")
            #expect(String(format: format, 3) == "3 etkinlik daha")
        }
    }

    @Test("the General island and multi-display controls are fully Turkish")
    func generalIslandSettingsAreTurkish() throws {
        let expectedTranslations = [
            "Island": "Ada",
            "Keeping the bar visible leaves an empty pill on screen while nothing is running.":
                "Çubuk görünür tutulduğunda, hiçbir etkinlik çalışmıyorken ekranda boş bir kapsül kalır.",
            "Keep the bar always visible": "Çubuğu her zaman görünür tut",
            "All displays": "Tüm ekranlar",
        ]

        try withTurkishBundle(
            for: "Sources/NotchFlowUI/Resources/Localizable.xcstrings"
        ) { bundle in
            for (key, translation) in expectedTranslations {
                #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == translation)
            }
        }
    }

    /// The picker names each language in that language, so a user who cannot
    /// read the current one can still find their own.
    @Test("the language picker names Turkish in Turkish")
    func languagePickerUsesEndonyms() {
        let options = LanguageOption.options(forLanguageCodes: ["tr", "en", "Base"])

        #expect(
            options == [
                LanguageOption(code: "en", displayName: "English"),
                LanguageOption(code: "tr", displayName: "Türkçe"),
            ]
        )
    }

    /// Compiles a catalog the way an app build does and hands its `tr.lproj` to
    /// `body`, so a lookup reads the shipped Turkish rather than the source
    /// language SwiftPM would otherwise serve.
    ///
    /// The bundle is passed to a closure rather than returned because `Bundle`
    /// reads its strings lazily: a helper that cleaned up on return would delete
    /// the compiled `.strings` before the first lookup touched them.
    private func withTurkishBundle(for catalog: String, body: (Bundle) throws -> Void) throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }

        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = [
            "xcstringstool", "compile",
            "--output-directory", output.path,
            repository.appendingPathComponent(catalog).path,
        ]
        try compiler.run()
        compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0, "xcstringstool failed for \(catalog)")

        let bundle = try #require(
            Bundle(url: output.appendingPathComponent("tr.lproj")),
            "\(catalog) compiled without a Turkish bundle"
        )
        try body(bundle)
    }
}
