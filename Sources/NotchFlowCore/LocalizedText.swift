import Foundation

/// Resolves a key against this module's String Catalog.
///
/// `docs/08-settings-and-localization.md` names String Catalogs as the single
/// localization mechanism, and every user-visible string in this module goes
/// through here rather than calling `String(localized:)` at each site. The
/// indirection buys one thing the scattered form cannot: `bundle: .module` is
/// stated once. A module-local catalog is invisible to a call that omits it —
/// the lookup silently falls back to the key, which reads as correct English
/// and hides the miss until a translated build.
///
/// The key is the English source text, which is what `xcstringstool` expects and
/// what keeps `swift test` honest: SwiftPM copies the catalog without compiling
/// it, so the fallback under test *is* the English the catalog would serve.
func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
