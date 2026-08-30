import Foundation
import NotchFlowCore

@MainActor
final class URLSchemeReceiver {
    var onMessage: ((IPCMessage) -> Void)?

    /// The same gate the loopback listener applies, because the URL scheme is
    /// the transport every installed hook actually uses — leaving it ungated
    /// would make each toggle a no-op for real agents.
    var preferences: AIIntegrationPreferences

    init(
        preferences: AIIntegrationPreferences = .default,
        onMessage: ((IPCMessage) -> Void)? = nil
    ) {
        self.preferences = preferences
        self.onMessage = onMessage
    }

    func handle(_ url: URL) {
        guard let message = try? IPCURLParser().parse(url),
              preferences.allows(message) else {
            return
        }
        onMessage?(message)
    }
}
