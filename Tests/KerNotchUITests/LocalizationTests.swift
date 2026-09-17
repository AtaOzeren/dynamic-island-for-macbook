import Foundation
import Testing

@testable import KerNotchUI

/// The shipped translations, checked the only way that is honest in a SwiftPM
/// test: by compiling the catalogs the way Xcode does and resolving against the
/// result.
///
/// SwiftPM copies `.xcstrings` into the bundle without compiling it, so
/// `String(localized:bundle: .module)` under `swift test` serves the English
/// fallback whatever locale it is handed — a test asserting on `.module` would
/// pass just as happily with every Turkish entry deleted. Running
/// `xcstringstool compile` produces the `tr.lproj` an app build produces, which
/// makes "Turkish resolves end to end" a claim about the shipped artefact
/// rather than about the source file.
@Suite("Localization")
struct LocalizationTests {
    /// Every language the app ships, checked the same way Turkish is: through a
    /// compiled catalog rather than through the source file, so the assertion is
    /// about the artefact the user actually runs.
    @Test(
        "every shipped language resolves from every catalog",
        arguments: [
            ("de", "Wird geladen", "Inselgröße", "KerNotch beenden"),
            ("es", "Cargando", "Tamaño de la isla", "Salir de KerNotch"),
            ("fr", "En charge", "Taille de l'îlot", "Quitter KerNotch"),
            ("it", "In carica", "Dimensione dell'isola", "Esci da KerNotch"),
            ("tr", "Şarj oluyor", "Ada boyutu", "KerNotch'dan Çık"),
        ]
    )
    func everyShippedLanguageResolves(
        language: String,
        charging: String,
        islandSize: String,
        quit: String
    ) throws {
        let expectations = [
            ("Sources/KerNotchCore/Resources/Localizable.xcstrings", "Charging", charging),
            ("Sources/KerNotchUI/Resources/Localizable.xcstrings", "Island size", islandSize),
            ("KerNotch/Localizable.xcstrings", "Quit KerNotch", quit),
        ]

        for (catalog, key, expected) in expectations {
            try withCompiledBundle(for: catalog, language: language) { bundle in
                #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == expected)
            }
        }
    }

    @Test(
        "every catalog resolves Turkish rather than falling back to English",
        arguments: [
            ("Sources/KerNotchCore/Resources/Localizable.xcstrings", "Charging", "Şarj oluyor"),
            ("Sources/KerNotchUI/Resources/Localizable.xcstrings", "Skip", "Atla"),
            ("KerNotch/Localizable.xcstrings", "Welcome to KerNotch", "KerNotch'a hoş geldiniz"),
        ]
    )
    func turkishResolvesFromEveryCatalog(catalog: String, key: String, turkish: String) throws {
        try withTurkishBundle(for: catalog) { bundle in
            #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == turkish)
        }
    }

    @Test("the island size control is fully Turkish")
    func islandSizeSettingIsTurkish() throws {
        try withTurkishBundle(for: "Sources/KerNotchUI/Resources/Localizable.xcstrings") { bundle in
            #expect(bundle.localizedString(forKey: "Island", value: nil, table: nil) == "Ada")
            #expect(bundle.localizedString(forKey: "Island size", value: nil, table: nil) == "Ada boyutu")
        }
        try withTurkishBundle(for: "Sources/KerNotchCore/Resources/Localizable.xcstrings") { bundle in
            #expect(bundle.localizedString(forKey: "Minimalist", value: nil, table: nil) == "Minimalist")
            #expect(bundle.localizedString(forKey: "Large", value: nil, table: nil) == "Büyük")
        }
    }

    @Test("the General multi-display control is fully Turkish")
    func generalMultiDisplaySettingIsTurkish() throws {
        let expectedTranslations = [
            "All displays": "Tüm ekranlar",
            "Show menu bar icon": "Menü çubuğu simgesini göster",
            "Restart KerNotch": "KerNotch'u yeniden başlat",
            "Restart required": "Yeniden başlatma gerekiyor",
        ]

        try withTurkishBundle(
            for: "Sources/KerNotchUI/Resources/Localizable.xcstrings"
        ) { bundle in
            for (key, translation) in expectedTranslations {
                #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == translation)
            }
        }
    }

    @Test("recording status copy is fully Turkish")
    func recordingStatusIsTurkish() throws {
        let expectedTranslations = [
            "Screen recording in progress": "Ekran kaydı yapılıyor",
            "Microphone in use": "Mikrofon kullanılıyor",
            "Screen recording and microphone in use": "Ekran kaydı ve mikrofon kullanılıyor",
        ]

        try withTurkishBundle(
            for: "Sources/KerNotchUI/Resources/Localizable.xcstrings"
        ) { bundle in
            for (key, translation) in expectedTranslations {
                #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == translation)
            }
        }
    }

    @Test("charging notification copy is fully Turkish")
    func chargingStatusIsTurkish() throws {
        let expectedTranslations = [
            "Unplugged": "Fişten Çekildi",
            "Plugged In": "Fişe Takılı",
            "Fully Charged": "Tam Şarj Oldu",
        ]

        try withTurkishBundle(
            for: "Sources/KerNotchUI/Resources/Localizable.xcstrings"
        ) { bundle in
            for (key, translation) in expectedTranslations {
                #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == translation)
            }
        }
    }

    @Test("music connection status is Turkish")
    func musicConnectionStatusIsTurkish() throws {
        try withTurkishBundle(
            for: "Sources/KerNotchCore/Resources/Localizable.xcstrings"
        ) { bundle in
            #expect(
                bundle.localizedString(forKey: "Connected", value: nil, table: nil)
                    == "Bağlandı"
            )
        }
    }

    @Test("AI tools tab uses the requested Turkish title")
    func aiToolsTabTitleIsTurkish() throws {
        try withTurkishBundle(
            for: "Sources/KerNotchUI/Resources/Localizable.xcstrings"
        ) { bundle in
            #expect(
                bundle.localizedString(forKey: "AI Integrations", value: nil, table: nil)
                    == "AI Araçları"
            )
        }
    }

    /// The picker names each language in that language, so a user who cannot
    /// read the current one can still find their own.
    @Test("the language picker names every shipped language in that language")
    func languagePickerUsesEndonyms() {
        let options = LanguageOption.options(
            forLanguageCodes: ["tr", "en", "de", "fr", "es", "it", "Base"]
        )

        #expect(
            options == [
                LanguageOption(code: "de", displayName: "Deutsch"),
                LanguageOption(code: "en", displayName: "English"),
                LanguageOption(code: "es", displayName: "Español"),
                LanguageOption(code: "fr", displayName: "Français"),
                LanguageOption(code: "it", displayName: "Italiano"),
                LanguageOption(code: "tr", displayName: "Türkçe"),
            ]
        )
    }

    /// Every catalog, swept key by key, so a key added tomorrow is covered
    /// without anyone remembering to extend a list here.
    private static let catalogs = [
        "Sources/KerNotchCore/Resources/Localizable.xcstrings",
        "Sources/KerNotchUI/Resources/Localizable.xcstrings",
        "KerNotch/Localizable.xcstrings",
    ]

    /// The acceptance criterion "every new key has a Turkish value", asked of
    /// the catalog itself rather than of a list someone has to maintain.
    @Test("every key in every catalog carries a Turkish value", arguments: catalogs)
    func everyKeyHasTurkish(catalog: String) throws {
        let untranslated = try Self.decodeCatalog(catalog)
            .strings
            .filter { $0.value.turkishValues.isEmpty }
            .keys
            .sorted()

        #expect(untranslated.isEmpty, "\(catalog) has keys with no Turkish value: \(untranslated)")
    }

    /// Presence in the source is not shipping: `xcstringstool` is what decides
    /// what `tr.lproj` actually contains. Resolving every simple key through the
    /// compiled bundle proves the whole catalog reaches a user, not just the
    /// handful named above.
    @Test("every catalog key resolves to its Turkish value once compiled", arguments: catalogs)
    func everyKeyResolvesToTurkish(catalog: String) throws {
        let expected = try Self.decodeCatalog(catalog).strings.compactMapValues(\.singleTurkishValue)

        try withTurkishBundle(for: catalog) { bundle in
            for (key, turkish) in expected.sorted(by: { $0.key < $1.key }) {
                #expect(
                    bundle.localizedString(forKey: key, value: nil, table: nil) == turkish,
                    "\(catalog) does not ship Turkish for \(key)"
                )
            }
        }
    }

    /// A key whose Turkish is byte-identical to its English is the shape an
    /// untranslated placeholder takes: present, resolvable, and still English.
    /// The exceptions are brand names and format-only strings, which have no
    /// words to translate, and loanwords Turkish spells exactly as English does.
    private static let untranslatableKeys: Set<String> = [
        "KerNotch",
        "Discord",
        "Minimalist",
        "activity.accessibility.headlineAndDetail",
        "activity.ai.blockedFootnote",
        "activity.ai.compactTitle",
        "activity.ai.sessionCountOverflow",
        "activity.ai.sessionName",
        "manualSetup.stepNumber",
    ]

    @Test("no key ships English under the Turkish locale", arguments: catalogs)
    func noKeyShipsEnglishAsTurkish(catalog: String) throws {
        let placeholders = try Self.decodeCatalog(catalog)
            .strings
            .filter { key, entry in
                Self.untranslatableKeys.contains(key) == false
                    && entry.turkishValues.isEmpty == false
                    && entry.turkishValues.sorted() == entry.englishValues.sorted()
            }
            .keys
            .sorted()

        #expect(placeholders.isEmpty, "\(catalog) leaves these keys in English: \(placeholders)")
    }

    private static func decodeCatalog(_ catalog: String) throws -> StringCatalog {
        try JSONDecoder().decode(
            StringCatalog.self,
            from: Data(contentsOf: repositoryRoot.appendingPathComponent(catalog))
        )
    }

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Only the shape this assertion reads: a key, its localizations, and the
    /// string units hiding under any plural or device variation.
    private struct StringCatalog: Decodable {
        let strings: [String: Entry]

        struct Entry: Decodable {
            let localizations: [String: Localization]?

            /// Empty when Turkish is missing entirely or left blank, which is
            /// the same failure to a reader either way.
            var turkishValues: [String] {
                let values = localizations?["tr"]?.stringValues ?? []
                return values.contains(where: \.isEmpty) ? [] : values
            }

            var englishValues: [String] {
                localizations?["en"]?.stringValues ?? []
            }

            /// The value a plain `localizedString(forKey:)` should return, or
            /// `nil` for plural entries, whose resolution the existing plural
            /// test covers with an actual count.
            var singleTurkishValue: String? {
                localizations?["tr"]?.stringUnit?.value
            }
        }

        struct Localization: Decodable {
            let stringUnit: StringUnit?
            let variations: [String: [String: Localization]]?

            var stringValues: [String] {
                if let stringUnit {
                    return [stringUnit.value]
                }
                return (variations ?? [:]).values.flatMap { $0.values.flatMap(\.stringValues) }
            }
        }

        struct StringUnit: Decodable {
            let value: String
        }
    }

    /// Compiles a catalog the way an app build does and hands its `tr.lproj` to
    /// `body`, so a lookup reads the shipped Turkish rather than the source
    /// language SwiftPM would otherwise serve.
    ///
    /// The bundle is passed to a closure rather than returned because `Bundle`
    /// reads its strings lazily: a helper that cleaned up on return would delete
    /// the compiled `.strings` before the first lookup touched them.
    private func withTurkishBundle(for catalog: String, body: (Bundle) throws -> Void) throws {
        try withCompiledBundle(for: catalog, language: "tr", body: body)
    }

    private func withCompiledBundle(
        for catalog: String,
        language: String,
        body: (Bundle) throws -> Void
    ) throws {
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
            Bundle(url: output.appendingPathComponent("\(language).lproj")),
            "\(catalog) compiled without a \(language) bundle"
        )
        try body(bundle)
    }
}
