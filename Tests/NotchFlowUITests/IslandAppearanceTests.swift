import AppKit
import SwiftUI
import Testing

@testable import NotchFlowUI

@Suite("IslandAppearance")
@MainActor
struct IslandAppearanceTests {
    @Test("auto follows whichever appearance the system is currently in")
    func autoFollowsTheSystem() {
        #expect(resolveIslandColorScheme(preference: .auto, system: .dark) == .dark)
        #expect(resolveIslandColorScheme(preference: .auto, system: .light) == .light)
    }

    @Test("an explicit preference overrides the system in both directions")
    func explicitPreferenceOverridesTheSystem() {
        #expect(resolveIslandColorScheme(preference: .light, system: .dark) == .light)
        #expect(resolveIslandColorScheme(preference: .dark, system: .light) == .dark)
    }

    @Test("auto leaves the panel without an appearance so AppKit keeps inheriting")
    func autoInheritsTheApplicationAppearance() {
        #expect(AppearancePreference.auto.nsAppearance == nil)
    }

    @Test("an explicit preference maps to the matching AppKit appearance")
    func explicitPreferenceMapsToAppKit() {
        #expect(AppearancePreference.light.nsAppearance?.name == .aqua)
        #expect(AppearancePreference.dark.nsAppearance?.name == .darkAqua)
    }

    @Test("the persisted raw values match the docs/08 settings table")
    func rawValuesMatchTheSettingsTable() {
        #expect(AppearancePreference.allCases.map(\.rawValue) == ["auto", "light", "dark"])
    }

    /// The panel hangs directly below the physical cutout, so it draws the
    /// notch's own black in both schemes — anything lighter or translucent
    /// reads as a separate card butted against the notch rather than as the
    /// notch growing downwards.
    @Test("the expanded panel stays notch black in both schemes")
    func expandedPanelIsNotchBlack() {
        #expect(islandExpandedSurface(scheme: .dark, reduceTransparency: false) == .notchBlack)
        #expect(islandExpandedSurface(scheme: .light, reduceTransparency: false) == .notchBlack)
    }

    @Test("Reduce Transparency leaves the already-opaque panel unchanged")
    func reduceTransparencyLeavesTheOpaquePanelUnchanged() {
        #expect(islandExpandedSurface(scheme: .dark, reduceTransparency: true) == .notchBlack)
        #expect(islandExpandedSurface(scheme: .light, reduceTransparency: true) == .notchBlack)
    }

    @Test("no surface is translucent once Reduce Transparency is on")
    func reduceTransparencyLeavesNothingTranslucent() {
        for scheme in [IslandColorScheme.light, .dark] {
            #expect(islandExpandedSurface(scheme: scheme, reduceTransparency: true).isTranslucent == false)
        }
    }

    @Test("the compact pill stays notch black in both schemes, so it reads as the cutout")
    func compactPillStaysNotchBlack() {
        #expect(islandCompactSurface(scheme: .dark) == .notchBlack)
        #expect(islandCompactSurface(scheme: .light) == .notchBlack)
    }

    @Test("the compact pill is opaque already, so Reduce Transparency has nothing to change")
    func compactPillIsAlreadyOpaque() {
        #expect(IslandSurface.notchBlack.isTranslucent == false)
    }

    @Test("every surface pairs with the foreground that contrasts against it")
    func everySurfaceContrastsWithItsForeground() {
        #expect(IslandSurface.notchBlack.foreground == .onDark)
        #expect(IslandSurface.material(.dark).foreground == .onDark)
        #expect(IslandSurface.solid(.dark).foreground == .onDark)
        #expect(IslandSurface.material(.light).foreground == .onLight)
        #expect(IslandSurface.solid(.light).foreground == .onLight)
    }

    @Test("changing the preference restyles the live panel instead of rebuilding it")
    func applyingAppearanceRestylesTheLivePanel() {
        let panel = NotchPanel(content: Color.clear)

        panel.applyAppearance(.dark)
        #expect(panel.appearance?.name == .darkAqua)

        panel.applyAppearance(.light)
        #expect(panel.appearance?.name == .aqua)

        panel.applyAppearance(.auto)
        #expect(panel.appearance == nil)
    }

    @Test("the panel starts on the caller's preference rather than always on auto")
    func panelHonoursTheInitialPreference() {
        let panel = NotchPanel(appearance: .dark, content: Color.clear)
        #expect(panel.appearance?.name == .darkAqua)
    }

    @Test("the window itself stays clear, so appearance only ever changes the content")
    func appearanceNeverMakesTheWindowOpaque() {
        let panel = NotchPanel(appearance: .light, content: Color.clear)
        #expect(panel.isOpaque == false)
        #expect(panel.backgroundColor == .clear)
    }
}
