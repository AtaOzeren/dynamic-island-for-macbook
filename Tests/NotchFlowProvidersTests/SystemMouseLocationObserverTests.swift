import AppKit
import CoreGraphics
import Testing

@testable import NotchFlowCore
@testable import NotchFlowProviders

@Suite("MouseLocationObserver")
@MainActor
struct SystemMouseLocationObserverTests {
    @MainActor
    private final class MonitorSpy {
        private(set) var installed: [ObjectIdentifier] = []
        private(set) var removed: [ObjectIdentifier] = []
        private(set) var masks: [NSEvent.EventTypeMask] = []
        private var report: (@MainActor (CGPoint) -> Void)?

        var liveMonitorCount: Int { installed.count - removed.count }

        func install(
            _ mask: NSEvent.EventTypeMask,
            _ report: @escaping @MainActor (CGPoint) -> Void
        ) -> [Any] {
            masks.append(mask)
            self.report = report

            let tokens = [NSObject(), NSObject()]
            installed.append(contentsOf: tokens.map(ObjectIdentifier.init))
            return tokens
        }

        func uninstall(_ token: Any) {
            removed.append(ObjectIdentifier(token as AnyObject))
        }

        /// A removed `NSEvent` monitor delivers nothing, so a spy that kept
        /// reporting after `uninstall` would pass a test the real API fails.
        func move(to location: CGPoint) {
            guard liveMonitorCount > 0 else { return }
            report?(location)
        }
    }

    private func makeObserver(spy: MonitorSpy) -> SystemMouseLocationObserver {
        SystemMouseLocationObserver(
            install: { spy.install($0, $1) },
            uninstall: { spy.uninstall($0) }
        )
    }

    @Test("reports every pointer move to the observer")
    func reportsPointerMoves() {
        let spy = MonitorSpy()
        let observer = makeObserver(spy: spy)
        var received: [CGPoint] = []

        observer.startObserving { received.append($0) }
        spy.move(to: CGPoint(x: 756, y: 970))
        spy.move(to: CGPoint(x: 100, y: 100))

        #expect(received == [CGPoint(x: 756, y: 970), CGPoint(x: 100, y: 100)])
    }

    @Test("watches movement and drags, never keyboard events that would need Accessibility")
    func watchesMovementOnly() throws {
        let spy = MonitorSpy()
        let observer = makeObserver(spy: spy)

        observer.startObserving { _ in }

        let mask = try #require(spy.masks.first)
        #expect(mask.contains(.mouseMoved))
        #expect(mask.contains(.leftMouseDragged))
        #expect(mask.contains(.keyDown) == false)
        #expect(mask.contains(.keyUp) == false)
    }

    @Test("watches locally as well as globally, since a global monitor is blind to our own pill")
    func watchesLocallyAndGlobally() {
        let spy = MonitorSpy()
        let observer = makeObserver(spy: spy)

        observer.startObserving { _ in }

        #expect(spy.liveMonitorCount == 2)
    }

    @Test("removes every monitor on stop, so an idle app never wakes on a pointer move")
    func stopRemovesEveryMonitor() {
        let spy = MonitorSpy()
        let observer = makeObserver(spy: spy)
        observer.startObserving { _ in }

        observer.stopObserving()

        #expect(spy.liveMonitorCount == 0)
        #expect(Set(spy.removed) == Set(spy.installed))
    }

    @Test("delivers nothing after stopping")
    func silentAfterStop() {
        let spy = MonitorSpy()
        let observer = makeObserver(spy: spy)
        var received: [CGPoint] = []
        observer.startObserving { received.append($0) }

        observer.stopObserving()
        spy.move(to: CGPoint(x: 756, y: 970))

        #expect(received.isEmpty)
    }

    @Test("never stacks monitors when restarted")
    func restartDoesNotStackMonitors() {
        let spy = MonitorSpy()
        let observer = makeObserver(spy: spy)

        observer.startObserving { _ in }
        observer.startObserving { _ in }

        #expect(spy.liveMonitorCount == 2)
    }

    @Test("removes every monitor when the observer is deallocated")
    func deallocationRemovesEveryMonitor() {
        let spy = MonitorSpy()

        do {
            let observer = makeObserver(spy: spy)
            observer.startObserving { _ in }
        }

        #expect(spy.liveMonitorCount == 0)
    }
}
