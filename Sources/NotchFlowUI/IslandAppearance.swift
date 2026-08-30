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
}

/// The compact pill's background.
///
/// Takes the scheme it ignores so the call site reads the same as the expanded
/// one, and so the day a light-mode pill is wanted the change lands here rather
/// than in the view.
public func islandCompactSurface(scheme _: IslandColorScheme) -> IslandSurface {
    .notchBlack
}

/// The expanded panel's background: translucent material normally, an opaque
/// fill of the same scheme under Reduce Transparency.
///
/// The setting swaps the material for a solid, never for a different scheme —
/// Reduce Transparency is an opacity preference, not an appearance one.
public func islandExpandedSurface(
    scheme: IslandColorScheme,
    reduceTransparency: Bool
) -> IslandSurface {
    reduceTransparency ? .solid(scheme) : .material(scheme)
}

/// The seam between the island's appearance policy and the system's Reduce
/// Transparency setting, mirroring `ReduceMotionQuerying`. Production reads
/// `NSWorkspace`; tests substitute a fake so both branches are assertable
/// without touching System Settings.
@MainActor
public protocol ReduceTransparencyQuerying: Sendable {
    var prefersReducedTransparency: Bool { get }
}

/// Reads Reduce Transparency from `NSWorkspace` at the moment a surface is about
/// to be drawn, on the same query-on-demand rationale as `SystemReduceMotion`.
@MainActor
public struct SystemReduceTransparency: ReduceTransparencyQuerying {
    public init() {}

    public var prefersReducedTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
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
