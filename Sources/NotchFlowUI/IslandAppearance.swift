import AppKit
import SwiftUI

import enum NotchFlowCore.SettingsAppearance

public typealias AppearancePreference = SettingsAppearance

extension SettingsAppearance {
    /// The appearance to force on the panel, or `nil` to keep inheriting from
    /// the application.
    ///
    /// `auto` deliberately yields `nil` rather than today's resolved appearance:
    /// an inherited `nil` lets AppKit re-resolve the panel when the system flips
    /// between light and dark, whereas a pinned value would freeze the island in
    /// whichever scheme happened to be active when the panel was built.
    public var nsAppearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// The scheme the island actually draws in, after the preference and the system
/// have been reconciled.
public enum IslandColorScheme: Equatable, Sendable {
    case light
    case dark
}

/// Which scheme the island draws in.
///
/// A pure function over the two inputs so the override rules are assertable
/// without switching System Settings mid-test.
public func resolveIslandColorScheme(
    preference: AppearancePreference,
    system: IslandColorScheme
) -> IslandColorScheme {
    switch preference {
    case .auto: system
    case .light: .light
    case .dark: .dark
    }
}

/// The foreground pairing for a surface. Named by the surface it sits on rather
/// than by its own colour, so a contrast assertion reads as the invariant it is
/// checking instead of as a colour comparison.
public enum IslandForeground: Equatable, Sendable {
    case onLight
    case onDark

    /// The SwiftUI style for text and icons drawn on the paired surface.
    public var style: HierarchicalShapeStyle { .primary }
}

/// A background the island draws behind its content.
///
/// Modelled as a value rather than as a SwiftUI `ShapeStyle` so the Reduce
/// Transparency rule in `docs/04-overlay-window.md` is inspectable: a test can
/// assert that nothing is translucent once the setting is on, which a resolved
/// style would not allow.
public enum IslandSurface: Equatable, Sendable {
    /// The compact pill. Always the notch's own black, in both schemes, because
    /// the pill's job is to read as an extension of the physical cutout.
    case notchBlack
    /// The translucent material behind the expanded panel.
    case material(IslandColorScheme)
    /// The opaque substitute for `material`, used under Reduce Transparency.
    case solid(IslandColorScheme)

    /// Whether the surface lets what is behind it through. The signal a Reduce
    /// Transparency assertion checks.
    public var isTranslucent: Bool {
        switch self {
        case .material: true
        case .notchBlack, .solid: false
        }
    }

    /// The foreground that contrasts against this surface.
    public var foreground: IslandForeground {
        switch self {
        case .notchBlack: .onDark
        case .material(let scheme), .solid(let scheme):
            switch scheme {
            case .light: .onLight
            case .dark: .onDark
            }
        }
    }

    /// Environment scheme descendants need for semantic text and controls.
    public var preferredColorScheme: ColorScheme {
        foreground == .onDark ? .dark : .light
    }
}

/// The compact pill's background.
///
/// Takes the scheme it ignores so the call site reads the same as the expanded
/// one, and so the day a light-mode pill is wanted the change lands here rather
/// than in the view.
public func islandCompactSurface(scheme _: IslandColorScheme) -> IslandSurface {
    .notchBlack
}

/// The expanded panel's background: the notch's own black, in both schemes and
/// with or without Reduce Transparency.
///
/// The panel hangs directly below the physical cutout, so anything translucent
/// or light reads as a separate floating card butted against the notch rather
/// than as the notch itself growing downwards. Matching the pill's `notchBlack`
/// is what makes the two read as one surface.
///
/// The parameters are kept even though neither changes the answer: every call
/// site passes the scheme and the Reduce Transparency flag it resolved, and
/// dropping them would push the decision back out into four views the day a
/// light-mode panel is wanted.
public func islandExpandedSurface(
    scheme _: IslandColorScheme,
    reduceTransparency _: Bool
) -> IslandSurface {
    .notchBlack
}

extension ColorScheme {
    /// The island's scheme for a SwiftUI environment value, so views resolve
    /// their surfaces from `NSApplication.effectiveAppearance` as it reaches
    /// them rather than by re-reading AppKit.
    var islandColorScheme: IslandColorScheme {
        self == .dark ? .dark : .light
    }
}

extension IslandSurface {
    /// The SwiftUI style to fill this surface's shape with.
    @ViewBuilder
    func fill(in shape: some InsettableShape) -> some View {
        switch self {
        case .notchBlack:
            shape.fill(.black)
        case .material:
            shape.fill(.ultraThinMaterial)
        case .solid(let scheme):
            shape.fill(scheme == .dark ? Color.black : Color.white)
        }
    }
}

/// The one type scale the expanded panel draws every card from.
///
/// Each card used to carry its own sizes: the generic row set its label from
/// `symbolSize` — the *glyph* budget — and came out at 15pt, music picked 13,
/// the agent card 12 and the timer 11. Four cards stacked on one surface then
/// read as four designs, and the eye had to re-anchor on every row.
///
/// Two steps carry everything a card says. `title` is what the card *is*
/// ("Mikrofon kullanılıyor", "OpenCode 1 · Working…"), `detail` is what it is
/// currently doing ("Tool completed", the artist, the elapsed time) — the same
/// relationship in every card, so the same pair of sizes says it everywhere.
///
/// `nestedTitle` and `nestedDetail` repeat that pair one step down for rows
/// drawn *inside* a card, which today means an instance's sub-agents. Nesting
/// steps the scale down rather than introducing a third relationship.
public struct IslandTypeScale: Equatable, Sendable {
    public static let `default` = IslandTypeScale()

    /// A card's headline.
    public let title: CGFloat
    /// A card's secondary line.
    public let detail: CGFloat
    /// The headline of a row nested inside a card.
    public let nestedTitle: CGFloat
    /// The secondary line of a row nested inside a card.
    public let nestedDetail: CGFloat
    /// The panel's footnote: smaller than anything a card draws, because it is
    /// not one of the things the user came to read.
    public let footnote: CGFloat

    public init(
        title: CGFloat = 12,
        detail: CGFloat = 10,
        nestedTitle: CGFloat = 10,
        nestedDetail: CGFloat = 9,
        footnote: CGFloat = 8
    ) {
        self.title = title
        self.detail = detail
        self.nestedTitle = nestedTitle
        self.nestedDetail = nestedDetail
        self.footnote = footnote
    }
}
