import Foundation

public struct AutoDismissDescriptor: Equatable, Sendable {
    public let after: Duration

    public init(after: Duration) {
        self.after = after
    }
}
