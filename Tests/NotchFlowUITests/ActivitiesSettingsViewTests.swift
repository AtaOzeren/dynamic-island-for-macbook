import SwiftUI
import Testing

@testable import NotchFlowCore
@testable import NotchFlowUI

/// The settings half of todo 64: denying a permission must leave "an explanatory
/// state in settings", and the explanation has to sit in the feature's own row
/// rather than anywhere that would read as blocking the rest of the app.
@Suite("Activities pane permissions")
@MainActor
struct ActivitiesSettingsViewTests {
    private final class Box<Value>: @unchecked Sendable {
        var value: Value
        init(_ value: Value) { self.value = value }
        var binding: Binding<Value> {
            Binding(get: { self.value }, set: { self.value = $0 })
        }
    }

    private static func access(
        _ status: AutomationPermissionStatus,
        _ target: MusicPlayerTarget = .spotify
    ) -> MusicAutomationAccess {
        MusicAutomationAccess(target: target, status: status)
    }

    private static func view(
        enabled: Set<ActivityProviderIdentifier> = [.music],
        automation: [MusicAutomationAccess] = [access(.notDetermined)],
        onRequest: @escaping (MusicPlayerTarget) -> Void = { _ in }
    ) -> ActivitiesSettingsView {
        ActivitiesSettingsView(
            enabledIdentifiers: Box(enabled).binding,
            musicAutomation: Box(automation).binding,
            onRequestAutomation: onRequest
        )
    }

    // MARK: - Where the explanation appears

    @Test("permission rows appear under a switched-on Music activity")
    func rowsAppearWhenMusicIsOn() {
        #expect(Self.view().isMusicAutomationSectionVisible)
    }

    /// Step 4 forbids blocking unrelated features, and a permission notice under
    /// a feature the user switched off is exactly that.
    @Test("permission rows disappear when Music is switched off")
    func rowsHideWhenMusicIsOff() {
        #expect(Self.view(enabled: [.timer]).isMusicAutomationSectionVisible == false)
    }

    /// The Direct build's MediaRemote backend sends no Apple Events, so it
    /// supplies no access values and must show no permission UI.
    @Test("a backend that needs no permission shows no permission rows")
    func rowsHideWithoutAnyAutomationTargets() {
        #expect(Self.view(automation: []).isMusicAutomationSectionVisible == false)
    }

    // MARK: - The button

    @Test("pressing Allow asks about that target only")
    func requestingReportsTheTarget() {
        let requested = Box<[MusicPlayerTarget]>([])
        let view = Self.view(
            automation: [Self.access(.notDetermined, .appleMusic)],
            onRequest: { requested.value.append($0) }
        )

        view.requestAutomation(for: .appleMusic)

        #expect(requested.value == [.appleMusic])
    }

    @Test("the pane renders whatever status it is given, for both targets")
    func paneRendersBothTargets() {
        let view = Self.view(automation: [
            Self.access(.granted, .spotify),
            Self.access(.denied, .appleMusic),
        ])

        #expect(view.isMusicAutomationSectionVisible)
        #expect(view.automationRows.map(\.target) == [.spotify, .appleMusic])
        #expect(view.automationRows.map(\.actionTitle) == [nil, nil])
    }
}
