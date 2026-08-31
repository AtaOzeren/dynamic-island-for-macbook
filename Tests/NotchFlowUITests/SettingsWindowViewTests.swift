import SwiftUI
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

/// Todo 60's acceptance criterion is "every documented setting is reachable and
/// functional". Reachable is the tab list; functional is a control that moves
/// the bound value rather than a private copy of it — the same write-through
/// property `AIIntegrationsSettingsViewTests` asserts for the AI pane.
@Suite("Settings window")
@MainActor
struct SettingsWindowViewTests {
    private final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
        var binding: Binding<Value> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    @Test("every documented pane is a tab")
    func everyPaneIsATab() {
        #expect(SettingsTab.allCases == [.general, .activities, .aiIntegrations, .about])
        for tab in SettingsTab.allCases {
            #expect(!tab.displayName.isEmpty)
            #expect(!tab.symbolName.isEmpty)
        }
    }

    @Test("the display picker offers the two rules plus every attached display")
    func displayPickerEnumeratesAttachedDisplays() {
        let box = Box(GeneralPreferences.default)
        let view = GeneralSettingsView(
            preferences: box.binding,
            availableDisplays: [
                DisplayDescription(name: "Built-in Retina Display", isBuiltIn: true),
                DisplayDescription(name: "Studio Display", isBuiltIn: false),
            ]
        )

        #expect(
            view.displayOptions == [
                .automatic,
                .builtIn,
                .named("Built-in Retina Display"),
                .named("Studio Display"),
            ])
        #expect(view.title(for: .named("Studio Display")) == "Studio Display")
    }

    @Test("every General control writes through to the preferences")
    func generalControlsWriteThrough() {
        let box = Box(GeneralPreferences.default)
        let view = GeneralSettingsView(preferences: box.binding, availableDisplays: [])

        view.displayTarget.wrappedValue = .named("Studio Display")
        view.launchAtLogin.wrappedValue = true
        view.appearance.wrappedValue = .dark

        #expect(box.value.displayTarget == .named("Studio Display"))
        #expect(box.value.launchAtLogin)
        #expect(box.value.appearance == .dark)
    }

    /// The three-way motion control maps onto a `Bool?`, so the round trip is
    /// worth asserting in both directions: a picker that cannot get back to
    /// "follow system" would strand the user on an override.
    @Test("the motion control round-trips through the optional override")
    func motionControlRoundTrips() {
        let box = Box(GeneralPreferences.default)
        let view = GeneralSettingsView(preferences: box.binding, availableDisplays: [])

        #expect(view.reducedMotion.wrappedValue == .followSystem)

        view.reducedMotion.wrappedValue = .alwaysReduce
        #expect(box.value.reducedMotionOverride == true)

        view.reducedMotion.wrappedValue = .neverReduce
        #expect(box.value.reducedMotionOverride == false)

        view.reducedMotion.wrappedValue = .followSystem
        #expect(box.value.reducedMotionOverride == nil)
    }

    @Test("every provider has a switch that writes through")
    func activityTogglesWriteThrough() {
        let box = Box(Set(ActivityProviderIdentifier.allCases))
        let view = ActivitiesSettingsView(enabledIdentifiers: box.binding)

        for identifier in ActivityProviderIdentifier.allCases {
            #expect(view.binding(for: identifier).wrappedValue)
            view.binding(for: identifier).wrappedValue = false
            #expect(!box.value.contains(identifier))
        }
        #expect(box.value.isEmpty)

        view.binding(for: .music).wrappedValue = true
        #expect(box.value == [.music])
    }

    @Test("the two recording sources are separately switchable")
    func recordingSourcesAreSeparateSwitches() {
        let box = Box(Set(ActivityProviderIdentifier.allCases))
        let view = ActivitiesSettingsView(enabledIdentifiers: box.binding)

        view.binding(for: .screenRecording).wrappedValue = false

        #expect(!box.value.contains(.screenRecording))
        #expect(box.value.contains(.audioRecording))
    }

    @Test("the language picker always offers a way back to the system default")
    func languagePickerOffersSystemDefault() {
        let box = Box(String?.none)
        let view = AboutSettingsView(
            information: AboutInformation(version: "1.0", build: "1", musicBackendName: "test"),
            languageOverride: box.binding,
            languages: [LanguageOption(code: "tr", displayName: "Türkçe")]
        )

        #expect(view.languageOptions.first == .systemDefault)
        #expect(view.selectedLanguage.wrappedValue == .systemDefault)

        view.selectedLanguage.wrappedValue = LanguageOption(code: "tr", displayName: "Türkçe")
        #expect(box.value == "tr")

        view.selectedLanguage.wrappedValue = .systemDefault
        #expect(box.value == nil)
    }

    /// An override the picker no longer lists — a language dropped between
    /// builds — must not leave the picker with no selection at all.
    @Test("an unlisted language override falls back to the system default")
    func unlistedOverrideFallsBack() {
        let box = Box(String?.some("xx"))
        let view = AboutSettingsView(
            information: AboutInformation(version: "1.0", build: "1", musicBackendName: "test"),
            languageOverride: box.binding
        )

        #expect(view.selectedLanguage.wrappedValue == .systemDefault)
    }
}
