import Foundation
import NotchFlowCore

@MainActor
final class URLSchemeReceiver {
    var onMessage: ((IPCMessage) -> Void)?

    init(onMessage: ((IPCMessage) -> Void)? = nil) {
        self.onMessage = onMessage
    }

    func handle(_ url: URL) {
        guard let message = try? IPCURLParser().parse(url) else {
            return
        }
        onMessage?(message)
    }
}
