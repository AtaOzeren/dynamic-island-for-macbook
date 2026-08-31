import Foundation

/// Resolves a key against this module's String Catalog.
///
/// The `NotchFlowUI` twin of `NotchFlowCore`'s helper of the same name. The two
/// are separate rather than shared because `.module` resolves per module: a
/// single helper living in Core would read Core's catalog for every UI string,
/// so the duplication is the mechanism working, not a missed extraction.
///
/// Every string this module draws goes through here rather than through
/// SwiftUI's `Text(_: LocalizedStringKey)`, which resolves against
/// `Bundle.main` — the *app's* bundle, not this one — and would miss the
/// catalog silently.
func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

/// Resolves an explicitly named key, for the strings whose English is pure
/// punctuation and placeholders.
///
/// `"%@, %@"` and `"%lld."` are legal catalog keys but not legal Swift symbols,
/// and `xcstringstool` fails the build rather than skipping them. Naming those
/// entries is the documented remedy, and it costs nothing at the call site: the
/// English still lives beside the call as `defaultValue`, so the source reads
/// the same as every other string here.
func localized(_ key: StaticString, default defaultValue: String.LocalizationValue) -> String {
    String(localized: key, defaultValue: defaultValue, bundle: .module)
}
