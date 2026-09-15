import Foundation
import KerNotchCore
import SwiftUI

/// What the Integrations pane shows about Discord that is not a preference.
public struct DiscordSettingsState: Equatable, Sendable {
    public var isDiscordInstalled: Bool
    /// Whether this build carries KerNotch's Discord application, and so can
    /// connect at all.
    public var isConnectionAvailable: Bool
    public var status: DiscordConnectionStatus

    public init(isDiscordInstalled: Bool, isConnectionAvailable: Bool, status: DiscordConnectionStatus) {
        self.isDiscordInstalled = isDiscordInstalled
        self.isConnectionAvailable = isConnectionAvailable
        self.status = status
    }
}

public enum DiscordSettingsAction: Equatable, Sendable {
    /// Raise Discord's authorization prompt.
    case connect
    /// Forget the stored authorization.
    case disconnect
    /// Start the connection over.
    case reconnect
}

/// The Integrations pane: Discord's switch, and the connection that names the
/// channel and leaves it.
///
/// The pane owns no state. It binds through to the composition root, for the
/// reason every pane does: the value the screen shows and the value the
/// integration runs on must be one value. There is deliberately no field for a
/// Discord application: KerNotch connects through its own, set per build.
public struct IntegrationsSettingsView: View {
    private static let downloadURL = URL(string: "https://discord.com/download")

    @Binding private var preferences: DiscordIntegrationPreferences
    private let discord: DiscordSettingsState
    private let metrics: SettingsPaneMetrics
    private let onPreferencesChange: (DiscordIntegrationPreferences) -> Void
    private let onAction: (DiscordSettingsAction) -> Void

    public init(
        preferences: Binding<DiscordIntegrationPreferences>,
        discord: DiscordSettingsState,
        metrics: SettingsPaneMetrics = .default,
        onPreferencesChange: @escaping (DiscordIntegrationPreferences) -> Void = { _ in },
        onAction: @escaping (DiscordSettingsAction) -> Void = { _ in }
    ) {
        _preferences = preferences
        self.discord = discord
        self.metrics = metrics
        self.onPreferencesChange = onPreferencesChange
        self.onAction = onAction
    }

    public var enabledBinding: Binding<Bool> {
        Binding(
            get: { preferences.isEnabled },
            set: { isEnabled in
                var updated = preferences
                updated.isEnabled = isEnabled
                preferences = updated
                onPreferencesChange(updated)
            }
        )
    }

    /// Switching on stays possible only while Discord is installed; switching
    /// off never stops being possible.
    public var isToggleEnabled: Bool {
        discord.isDiscordInstalled || preferences.isEnabled
    }

    /// A build without KerNotch's Discord application has no connection to
    /// offer, so the section is left out rather than shown disabled forever.
    public var showsVoiceChannelSection: Bool {
        discord.isConnectionAvailable
    }

    public static func statusText(for status: DiscordConnectionStatus) -> String? {
        switch status {
        case .inactive: nil
        case .discordUnavailable: localized("Waiting for Discord to open.")
        case .connecting: localized("Connecting to Discord…")
        case .needsAuthorization: localized("Ready to connect.")
        case .awaitingApproval: localized("Approve KerNotch in Discord.")
        case .connected(let username?): localized("Connected as \(username).")
        case .connected(nil): localized("Connected.")
        case .failed(.invalidClientID): localized("Discord did not recognize KerNotch.")
        case .failed(.authorizationDenied): localized("The request was declined in Discord.")
        case .failed(.authorizationFailed):
            localized(
                "Discord did not complete the connection. KerNotch's Discord connection may not be available for your account yet; the microphone badge still works."
            )
        }
    }

    /// The one button the connection row offers for `status`.
    public static func connectionAction(for status: DiscordConnectionStatus) -> DiscordSettingsAction {
        if case .connected = status {
            return .disconnect
        }
        return status.canReconnect ? .reconnect : .connect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            discordSection
            if showsVoiceChannelSection {
                Divider()
                voiceChannelSection
                    .disabled(preferences.isEnabled == false)
            }
        }
        .settingsPaneFrame(metrics)
    }

    private var discordSection: some View {
        SettingsSection(
            title: localized("Discord"),
            caption: localized("Shows Discord voice calls on the island in place of the microphone indicator."),
            metrics: metrics
        ) {
            Toggle(localized("Show Discord calls"), isOn: enabledBinding)
                .disabled(isToggleEnabled == false)

            if discord.isDiscordInstalled == false {
                HStack {
                    Label(localized("Discord is not installed on this Mac."), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: metrics.rowSpacing)
                    if let url = Self.downloadURL {
                        Link(localized("Get Discord"), destination: url)
                    }
                }
            }
        }
    }

    private var voiceChannelSection: some View {
        SettingsSection(
            title: localized("Voice channel"),
            caption: localized(
                "Connect Discord to see the channel name and leave the channel from the island. Discord asks you to approve KerNotch once."
            ),
            metrics: metrics
        ) {
            connectionRow
        }
    }

    private var connectionRow: some View {
        HStack(alignment: .firstTextBaseline) {
            if let text = Self.statusText(for: discord.status) {
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: metrics.rowSpacing)
            switch Self.connectionAction(for: discord.status) {
            case .disconnect:
                Button(localized("Disconnect")) { onAction(.disconnect) }
            case .reconnect:
                Button(localized("Try Again")) { onAction(.reconnect) }
            case .connect:
                Button(localized("Connect")) { onAction(.connect) }
                    .disabled(discord.status.canAuthorize == false)
            }
        }
    }
}
