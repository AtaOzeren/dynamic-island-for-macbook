public typealias ActivityObserver = (any Activity) -> Void

public protocol ActivityProvider: AnyObject {
    func startObserving(_ observer: @escaping ActivityObserver)
    func stopObserving()
}

public final class ActivityProviderRegistry {
    private let providers: [any ActivityProvider]
    private var observer: ActivityObserver?

    public init(providers: [any ActivityProvider]) {
        self.providers = providers
    }

    public func startObserving(_ observer: @escaping ActivityObserver) {
        stopObserving()
        self.observer = observer

        for provider in providers {
            provider.startObserving { [weak self] activity in
                self?.observer?(activity)
            }
        }
    }

    public func stopObserving() {
        guard observer != nil else {
            return
        }

        observer = nil

        for provider in providers {
            provider.stopObserving()
        }
    }

    deinit {
        stopObserving()
    }
}
