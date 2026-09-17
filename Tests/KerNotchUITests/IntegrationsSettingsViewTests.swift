import Foundation
import SwiftUI
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

/// The Integrations pane's rules, driven through the same bindings and helpers
/// a press or a keystroke uses.
@Suite("IntegrationsSettingsView")
@MainActor
struct IntegrationsSettingsViewTests {
    private final class Store: @unchecked Sendable {
        var preferences: DiscordIntegrationPreferences
        var published: [DiscordIntegrationPreferences] = []

        init(_ preferences: DiscordIntegrationPreferences = .default) {
            self.preferences = preferences
        }

        var binding: Binding<DiscordIntegrationPreferences> {
            Binding(get: { self.preferences }, set: { self.preferences = $0 })
        }
    }

    private static let installed = DiscordSettingsState(
        isDiscordInstalled: true,
        isConnectionAvailable: true,
        status: .inactive
    )

    private static func makeView(
        _ store: Store,
        discord: DiscordSettingsState = installed
    ) -> IntegrationsSettingsView {
        IntegrationsSettingsView(
            preferences: store.binding,
            discord: discord,
            onPreferencesChange: { store.published.append($0) }
        )
    }

    @Test("the switch publishes the value the integration runs on")
    func switchPublishes() {
        let store = Store()
        let view = Self.makeView(store)

        view.enabledBinding.wrappedValue = true

        #expect(store.preferences.isEnabled)
        #expect(store.published == [DiscordIntegrationPreferences(isEnabled: true)])
    }

    @Test("cannot be switched on without Discord installed, but can always be switched off")
    func toggleNeedsDiscordToTurnOn() {
        let missing = DiscordSettingsState(isDiscordInstalled: false, isConnectionAvailable: true, status: .inactive)

        #expect(Self.makeView(Store(), discord: missing).isToggleEnabled == false)
        #expect(Self.makeView(Store(DiscordIntegrationPreferences(isEnabled: true)), discord: missing).isToggleEnabled)
    }

    @Test("offers the connection only in a build that carries KerNotch's Discord application")
    func voiceChannelSectionFollowsBuild() {
        let withoutApplication = DiscordSettingsState(
            isDiscordInstalled: true,
            isConnectionAvailable: false,
            status: .inactive
        )

        #expect(Self.makeView(Store()).showsVoiceChannelSection)
        #expect(Self.makeView(Store(), discord: withoutApplication).showsVoiceChannelSection == false)
    }

    @Test(
        "says something for every connection state",
        arguments: [
            DiscordConnectionStatus.discordUnavailable, .connecting, .needsAuthorization, .awaitingApproval,
            .connected(username: "webh0sta"), .connected(username: nil), .failed(.invalidClientID),
            .failed(.authorizationDenied), .failed(.authorizationFailed),
        ]
    )
    func describesEveryStatus(status: DiscordConnectionStatus) {
        #expect(IntegrationsSettingsView.statusText(for: status)?.isEmpty == false)
    }

    @Test("says nothing while the integration is off")
    func inactiveSaysNothing() {
        #expect(IntegrationsSettingsView.statusText(for: .inactive) == nil)
    }

    /// Before Discord approves KerNotch's application, an account that is not
    /// one of its testers cannot finish connecting; the message says so rather
    /// than blaming a setting the user cannot see.
    @Test("explains an incomplete connection without naming developer settings")
    func incompleteConnectionIsExplained() throws {
        let text = try #require(IntegrationsSettingsView.statusText(for: .failed(.authorizationFailed)))

        #expect(text.contains("Public Client") == false)
        #expect(text.contains("Client ID") == false)
    }

    @Test(
        "offers Try Again wherever the connection is waiting on Discord",
        arguments: [
            DiscordConnectionStatus.discordUnavailable, .connecting, .awaitingApproval, .failed(.invalidClientID),
        ]
    )
    func offersReconnect(status: DiscordConnectionStatus) {
        #expect(IntegrationsSettingsView.connectionAction(for: status) == .reconnect)
    }

    @Test("offers Connect when the user can authorize, and Disconnect once connected")
    func offersConnectAndDisconnect() {
        #expect(IntegrationsSettingsView.connectionAction(for: .needsAuthorization) == .connect)
        #expect(IntegrationsSettingsView.connectionAction(for: .failed(.authorizationDenied)) == .connect)
        #expect(IntegrationsSettingsView.connectionAction(for: .inactive) == .connect)
        #expect(IntegrationsSettingsView.connectionAction(for: .connected(username: nil)) == .disconnect)
    }

    @Test("the settings window hides the Integrations tab in a build without Discord")
    func tabFollowsAvailability() {
        let general = GeneralPreferences.default
        let makeWindow = { (discord: DiscordSettingsState?) in
            SettingsWindowView(
                general: .constant(general),
                enabledIdentifiers: .constant([]),
                aiPreferences: .constant(.default),
                languageOverride: .constant(nil),
                availableDisplays: [],
                information: AboutInformation(version: "1.0", build: "1", musicBackendName: "test"),
                discordSettings: discord
            )
        }

        #expect(makeWindow(nil).visibleTabs.contains(.integrations) == false)
        #expect(makeWindow(Self.installed).visibleTabs == SettingsTab.allCases)
    }
}

@Suite("Discord call presentation")
@MainActor
struct DiscordCallPresentationTests {
    private static let lobby = DiscordVoiceChannel(name: "Lobby", serverName: "Ocean View Hotel")

    @Test("names the channel and its server")
    func namesChannel() {
        let presentation = DiscordCallPresentation(activity: DiscordCallActivity(channel: Self.lobby, isMuted: false))

        #expect(presentation.title == "Lobby")
        #expect(presentation.detail == "Ocean View Hotel")
        #expect(presentation.leaveAction?.intent == .leaveDiscordVoiceChannel)
    }

    @Test("says only that a call is on without the RPC connection")
    func unknownChannel() {
        let presentation = DiscordCallPresentation(activity: DiscordCallActivity(channel: nil, isMuted: nil))

        #expect(presentation.title == "In a Discord call")
        #expect(presentation.detail == nil)
        #expect(presentation.leaveAction == nil)
        #expect(presentation.isMuted == false)
    }

    @Test("names a private call that has no channel name")
    func privateCall() {
        let call = DiscordCallActivity(channel: DiscordVoiceChannel(name: "", serverName: nil), isMuted: false)

        #expect(DiscordCallPresentation(activity: call).title == "Private call")
    }

    @Test("slashes the microphone and says so while muted")
    func muted() {
        let presentation = DiscordCallPresentation(activity: DiscordCallActivity(channel: Self.lobby, isMuted: true))

        #expect(presentation.microphoneSymbolName == "mic.slash.fill")
        #expect(presentation.accessibilityLabel.hasPrefix("Muted"))
    }

    /// The reported defect: deafening switches the microphone off too, but
    /// Discord leaves its mute flag alone — so the island drew a live
    /// microphone for someone who could neither speak nor hear.
    @Test("shows deafened as its own state, not as a live microphone")
    func deafened() {
        let presentation = DiscordCallPresentation(
            activity: DiscordCallActivity(channel: Self.lobby, isMuted: false, isDeafened: true)
        )

        #expect(presentation.audioState == .deafened)
        #expect(presentation.isMuted, "a deafened microphone is not live")
        #expect(presentation.microphoneSymbolName == "headphones.slash")
        #expect(presentation.accessibilityLabel.hasPrefix("Deafened"))
    }

    @Test("deafened outranks muted, since it is both")
    func deafenedOutranksMuted() {
        let presentation = DiscordCallPresentation(
            activity: DiscordCallActivity(channel: Self.lobby, isMuted: true, isDeafened: true)
        )

        #expect(presentation.audioState == .deafened)
    }

    @Test("a call that is neither muted nor deafened reads as live")
    func live() {
        let presentation = DiscordCallPresentation(
            activity: DiscordCallActivity(channel: Self.lobby, isMuted: false, isDeafened: false)
        )

        #expect(presentation.audioState == .live)
        #expect(presentation.microphoneSymbolName == "mic.fill")
    }

    @Test("gets a compact slot of its own, distinct from the microphone indicator")
    func compactSlot() {
        let slot = discordCallCompactSlot(for: DiscordCallActivity(channel: nil, isMuted: false))

        #expect(slot.discordCall != nil)
        #expect(slot.recordingIndicator == nil)
        #expect(slot.id == DiscordCallActivity.identity.rawValue)
    }

    @Test("renders with its own expanded view at the standard row height")
    func expandedRenderer() {
        let call = DiscordCallActivity(channel: Self.lobby, isMuted: false)

        #expect(expandedItemRenderer(for: call) == .discordCall)
        #expect(expandedItemHeight(for: call) == ExpandedPanelMetrics.default.rowHeight)
    }

    @Test("the leave button routes through the primary action, and only when it exists")
    func leaveRoutes() {
        var presses = 0
        let connected = DiscordCallActivityView(
            activity: DiscordCallActivity(channel: Self.lobby, isMuted: false),
            onLeave: { presses += 1 }
        )
        let passive = DiscordCallActivityView(
            activity: DiscordCallActivity(channel: nil, isMuted: nil),
            onLeave: { presses += 1 }
        )

        connected.leave()
        passive.leave()

        #expect(presses == 1)
    }
}

@Suite("SVG path data")
struct SVGPathDataTests {
    @Test("draws the bundled Discord symbol")
    func parsesBundledSymbol() throws {
        let artwork = try #require(DiscordSymbolArtwork.artwork)

        #expect(artwork.viewBox == CGRect(x: 0, y: 0, width: 126.644, height: 96))
        #expect(artwork.path.boundingRect.width > 120)
        #expect(artwork.path.boundingRect.height > 90)
    }

    @Test("reads compact number runs and relative commands")
    func parsesCompactNumbers() throws {
        let path = try #require(SVGPathData.path(from: "M10,10l-.5-.5h2v2Z"))

        #expect(path.boundingRect == CGRect(x: 9.5, y: 9.5, width: 2, height: 2))
    }

    @Test("reflects the previous control point for a smooth curve")
    func smoothCurve() throws {
        let path = try #require(SVGPathData.path(from: "M0,0C0,10,10,10,10,0S20,-10,20,0"))

        #expect(path.boundingRect.maxX == 20)
        #expect(path.boundingRect.minY < 0)
    }

    @Test("refuses unsupported commands and dangling numbers rather than drawing half a mark")
    func rejectsMalformedData() {
        #expect(SVGPathData.path(from: "M0,0A5,5,0,0,1,10,10") == nil)
        #expect(SVGPathData.path(from: "M0,0L10") == nil)
        #expect(SVGPathData.path(from: "M0,0Z5") == nil)
    }
}
