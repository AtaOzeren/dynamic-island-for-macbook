import Foundation
import KerNotchCore
import SwiftUI

/// What the Integrations pane shows about Discord that is not a preference.
public struct DiscordSettingsState: Equatable, Sendable {
    public var isDiscordInstalled: Bool
    public var status: DiscordConnectionStatus

    public init(isDiscordInstalled: Bool, status: DiscordConnectionStatus) {
        self.isDiscordInstalled = isDiscordInstalled
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

/// The Integrations pane: Discord's switch, and the optional connection that
/// names the channel and leaves it.
///
/// The pane owns only the Client ID being typed. Everything else binds through
/// to the composition root, for the reason every pane does: the value the
/// screen shows and the value the integration runs on must be one value.
public struct IntegrationsSettingsView: View {
    private static let developerPortalURL = URL(string: "https://discord.com/developers/applications")
    private static let downloadURL = URL(string: "https://discord.com/download")
    /// How long typing pauses before the field's text is taken as the Client
    /// ID. A 19-digit ID passes validation at 17 digits already, and every
    /// published ID reconnects to Discord, so each keystroke must not.
    private static let clientIDCommitDelay = Duration.milliseconds(700)

    @Binding private var preferences: DiscordIntegrationPreferences
    private let discord: DiscordSettingsState
    private let metrics: SettingsPaneMetrics
    private let onPreferencesChange: (DiscordIntegrationPreferences) -> Void
    private let onAction: (DiscordSettingsAction) -> Void

    /// What is in the field, which is not yet the Client ID until it parses.
    @State private var clientIDDraft: String

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
        _clientIDDraft = State(initialValue: preferences.wrappedValue.clientID?.rawValue ?? "")
    }

    public var enabledBinding: Binding<Bool> {
        Binding(
            get: { preferences.isEnabled },
            set: { isEnabled in
                var updated = preferences
                updated.isEnabled = isEnabled
                publish(updated)
            }
        )
    }

    /// Publishes a Client ID only once the text is one, and clears it when the
    /// field is emptied. A half-pasted ID is kept in the field, where the user
    /// can see and fix it, rather than stored.
    public func updateClientID(from text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientID = DiscordClientID(rawValue: trimmed)
        guard trimmed.isEmpty || clientID != nil, clientID != preferences.clientID else { return }

        var updated = preferences
        updated.clientID = clientID
        publish(updated)
    }

    /// Brings the field back in line with a stored ID that changed elsewhere,
    /// without overwriting text that already means the same ID.
    private func syncDraft(with clientID: DiscordClientID?) {
        guard DiscordClientID(rawValue: clientIDDraft) != clientID else { return }
        clientIDDraft = clientID?.rawValue ?? ""
    }

    public static func isMalformedClientID(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false && DiscordClientID(rawValue: trimmed) == nil
    }

    /// Switching on stays possible only while Discord is installed; switching
    /// off never stops being possible.
    public var isToggleEnabled: Bool {
        discord.isDiscordInstalled || preferences.isEnabled
    }

    public static func statusText(
        for status: DiscordConnectionStatus,
        hasClientID: Bool
    ) -> String? {
        switch status {
        case .inactive: hasClientID ? nil : localized("Paste a Client ID to connect.")
        case .discordUnavailable: localized("Waiting for Discord to open.")
        case .connecting: localized("Connecting to Discord…")
        case .needsAuthorization: localized("Ready to connect.")
        case .awaitingApproval: localized("Approve KerNotch in Discord.")
        case .connected(let username?): localized("Connected as \(username).")
        case .connected(nil): localized("Connected.")
        case .failed(.invalidClientID): localized("Discord does not recognize this Client ID.")
        case .failed(.authorizationDenied): localized("The request was declined in Discord.")
        case .failed(.authorizationFailed): localized("Discord did not issue a token. Check that Public Client is on.")
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
            Divider()
            voiceChannelSection
                .disabled(preferences.isEnabled == false)
        }
        .settingsPaneFrame(metrics)
    }

    private func publish(_ updated: DiscordIntegrationPreferences) {
        preferences = updated
        onPreferencesChange(updated)
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
                "Optional. Connect Discord to see the channel name and leave the channel from the island. KerNotch connects through a Discord application you own, without a client secret."
            ),
            metrics: metrics
        ) {
            setupSteps
            clientIDField
            connectionRow
        }
    }

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing / 2) {
            Text(localized("1. Create an application in the Discord Developer Portal."))
            Text(localized("2. On its OAuth2 page, turn on Public Client."))
            Text(localized("3. Paste its Client ID here, press Connect, and approve KerNotch in Discord."))
            if let url = Self.developerPortalURL {
                Link(localized("Open Developer Portal"), destination: url)
            }
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var clientIDField: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing / 2) {
            TextField(localized("Client ID"), text: $clientIDDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { updateClientID(from: clientIDDraft) }
                .task(id: clientIDDraft) {
                    // Cancellation — another keystroke — is the only error
                    // Task.sleep throws here, and it means "not yet".
                    try? await Task.sleep(for: Self.clientIDCommitDelay)
                    guard Task.isCancelled == false else { return }
                    updateClientID(from: clientIDDraft)
                }
                .onChange(of: preferences.clientID) { _, clientID in
                    syncDraft(with: clientID)
                }

            if Self.isMalformedClientID(clientIDDraft) {
                Text(localized("That is not a Discord application ID."))
                    .font(.system(size: metrics.footnoteSize))
                    .foregroundStyle(.red)
            }
        }
    }

    private var connectionRow: some View {
        HStack {
            if let text = Self.statusText(for: discord.status, hasClientID: preferences.clientID != nil) {
                Text(text)
                    .foregroundStyle(.secondary)
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
