import NotchFlowCore
import SwiftUI

/// The Activities pane: one switch per provider the user can turn off.
///
/// The switch does not merely hide a card — the composition root stops the
/// provider observing, which is why the caption names what stops rather than
/// what disappears.
public struct ActivitiesSettingsView: View {
    @Binding private var enabledIdentifiers: Set<ActivityProviderIdentifier>
    @Binding private var musicAutomation: [MusicAutomationAccess]

    private let metrics: SettingsPaneMetrics
    private let automationRequestsInProgress: Set<MusicPlayerTarget>
    private let onRequestAutomation: (MusicPlayerTarget) -> Void

    public init(
        enabledIdentifiers: Binding<Set<ActivityProviderIdentifier>>,
        musicAutomation: Binding<[MusicAutomationAccess]> = .constant([]),
        metrics: SettingsPaneMetrics = .default,
        automationRequestsInProgress: Set<MusicPlayerTarget> = [],
        onRequestAutomation: @escaping (MusicPlayerTarget) -> Void = { _ in }
    ) {
        self._enabledIdentifiers = enabledIdentifiers
        self._musicAutomation = musicAutomation
        self.metrics = metrics
        self.automationRequestsInProgress = automationRequestsInProgress
        self.onRequestAutomation = onRequestAutomation
    }

    /// The permission rows are shown only under a Music switch that is on.
    ///
    /// Step 4 of the flow in `docs/09-security-privacy-permissions.md` requires
    /// the explanation to appear "in place, in that feature's settings row", and
    /// a permission notice under a feature the user has switched off is not that
    /// — it is an unrelated feature being blocked, which the same paragraph
    /// rules out.
    public var isMusicAutomationSectionVisible: Bool {
        enabledIdentifiers.contains(.music) && !musicAutomation.isEmpty
    }

    public var automationRows: [MusicAutomationAccess] {
        musicAutomation
    }

    public func requestAutomation(for target: MusicPlayerTarget) {
        guard canRequestAutomation else { return }
        onRequestAutomation(target)
    }

    public func isAutomationRequestInProgress(for target: MusicPlayerTarget) -> Bool {
        automationRequestsInProgress.contains(target)
    }

    public var canRequestAutomation: Bool {
        automationRequestsInProgress.isEmpty
    }

    public func binding(for identifier: ActivityProviderIdentifier) -> Binding<Bool> {
        Binding(
            get: { enabledIdentifiers.contains(identifier) },
            set: { isEnabled in
                if isEnabled {
                    enabledIdentifiers.insert(identifier)
                } else {
                    enabledIdentifiers.remove(identifier)
                }
            }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            activitiesSection
            if isMusicAutomationSectionVisible {
                Divider()
                musicAutomationSection
            }
        }
        .settingsPaneFrame(metrics)
    }

    private var activitiesSection: some View {
        SettingsSection(
            title: localized("Activities"),
            caption: localized("A switched-off activity stops being observed, not just hidden."),
            metrics: metrics
        ) {
            ForEach(ActivityProviderIdentifier.allCases, id: \.self) { identifier in
                Toggle(isOn: binding(for: identifier)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(identifier.displayName)
                        Text(identifier.caption)
                            .font(.system(size: metrics.footnoteSize))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var musicAutomationSection: some View {
        SettingsSection(
            title: localized("Music control"),
            caption: localized("NotchFlow asks macOS for each player separately, and only when you press the button."),
            metrics: metrics
        ) {
            ForEach(automationRows, id: \.target) { access in
                automationRow(access)
            }
        }
    }

    private func automationRow(_ access: MusicAutomationAccess) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(access.target.displayName)
            Text(access.explanation)
                .font(.system(size: metrics.footnoteSize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let connectionTitle = access.connectionTitle {
                Label(connectionTitle, systemImage: "checkmark.circle.fill")
                    .font(.system(size: metrics.footnoteSize, weight: .medium))
                    .foregroundStyle(.green)
            } else if isAutomationRequestInProgress(for: access.target) {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(localized("Connecting…"))
                }
                .font(.system(size: metrics.footnoteSize))
                .foregroundStyle(.secondary)
            } else if let actionTitle = access.actionTitle {
                Button(actionTitle) { requestAutomation(for: access.target) }
                    .font(.system(size: metrics.footnoteSize))
                    .disabled(canRequestAutomation == false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
