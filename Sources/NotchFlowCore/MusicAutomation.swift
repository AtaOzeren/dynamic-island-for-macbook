import Foundation

/// The two scriptable players the App Store build is allowed to talk to.
///
/// The list is closed on purpose. `docs/06-activity-providers.md` scopes the
/// `com.apple.security.scripting-targets` entitlement to exactly these two
/// bundle identifiers, so a third case here would be a case the sandbox refuses
/// to serve — the enum is the entitlement, expressed in Swift.
public enum MusicPlayerTarget: CaseIterable, Hashable, Sendable {
    case spotify
    case appleMusic

    public var bundleIdentifier: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .appleMusic: "com.apple.Music"
        }
    }

    /// The name shown as the audio source. Deliberately not derived from the
    /// bundle identifier: this is user-visible text, and "Music" is what the app
    /// is called.
    public var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Music"
        }
    }

    /// The distributed notification the app posts on track and play-state
    /// change, per `docs/06-activity-providers.md`. It is a wake-up signal only:
    /// its payload is not trusted for state, which is read back from the app.
    public var playbackNotificationName: Notification.Name {
        switch self {
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .appleMusic: Notification.Name("com.apple.Music.playerInfo")
        }
    }
}

/// Where one Apple Events target stands with the system, as three states rather
/// than a `Bool`.
///
/// Two states would collapse the only distinction the permission flow in
/// `docs/09-security-privacy-permissions.md` turns on: `notDetermined` is the
/// state where a prompt is still available and NotchFlow owes the user an
/// explanation first, while `denied` is the state where prompting is both
/// useless — the system answers from its record without showing anything — and
/// forbidden, because the flow says NotchFlow "does not nag, re-prompt on a
/// timer, or block unrelated features". Collapsing them would make those two
/// obligations indistinguishable at the call site.
public enum AutomationPermissionStatus: Equatable, Sendable {
    /// No decision recorded; asking will show the system prompt.
    case notDetermined
    /// The user allowed automation of this app.
    case granted
    /// The user refused, or later revoked in System Settings. Asking again
    /// changes nothing.
    case denied
}

/// What NotchFlow may currently do with one music app, derived from that app's
/// permission status.
///
/// This exists so that the rule "no permission is requested at launch" is a
/// property of a type rather than a convention every call site must remember.
/// The provider asks `canQuery`; nothing in the observation path can reach a
/// state where sending an Apple Event to a `notDetermined` target is expressible,
/// so the wake-up notifications that arrive with no window open cannot surface a
/// prompt. Only the settings row, which is a user action by definition, asks for
/// `request`.
public struct MusicAutomationAccess: Equatable, Sendable {
    public let target: MusicPlayerTarget
    public let status: AutomationPermissionStatus

    public init(target: MusicPlayerTarget, status: AutomationPermissionStatus) {
        self.target = target
        self.status = status
    }

    /// Whether an Apple Event may be sent to this app right now.
    ///
    /// False for `notDetermined` on purpose: the first event is what triggers
    /// the system prompt, so treating "not yet asked" as permission to try is
    /// exactly the launch-time prompt the flow forbids.
    public var canQuery: Bool {
        status == .granted
    }

    /// Whether the settings row should offer to ask. Only `notDetermined` can be
    /// asked: a granted target has nothing to ask for, and a denied one would
    /// get a prompt the system silently swallows.
    public var isRequestable: Bool {
        status == .notDetermined
    }

    /// The plain-language explanation shown in NotchFlow's own UI *before* the
    /// system prompt, which is step 2 of the flow in
    /// `docs/09-security-privacy-permissions.md`.
    ///
    /// Each state gets its own sentence because the row has to say what is true
    /// now, not one message that hedges: an explanation offered next to a
    /// working feature reads as a warning, and a promise of a prompt shown to a
    /// user who already refused reads as a lie.
    public var explanation: String {
        switch status {
        case .notDetermined:
            localized("""
                NotchFlow will ask macOS for permission to control \(target.displayName), \
                so the notch can show what is playing and its buttons can control playback. \
                Nothing is sent anywhere; NotchFlow only talks to \(target.displayName) on this Mac.
                """)
        case .granted:
            localized("NotchFlow can show and control what \(target.displayName) is playing.")
        case .denied:
            localized("""
                \(target.displayName) control is off because macOS permission was declined. \
                Everything else in NotchFlow keeps working. \
                To turn it on, allow NotchFlow for \(target.displayName) in \
                System Settings › Privacy & Security › Automation.
                """)
        }
    }

    /// The button's label, or `nil` when there is nothing to press. A denied row
    /// deliberately has no button: the only remedy is System Settings, which the
    /// explanation names, and a button that re-prompted into silence is the nag
    /// the flow rules out.
    public var actionTitle: String? {
        isRequestable ? localized("Allow \(target.displayName)…") : nil
    }
}
