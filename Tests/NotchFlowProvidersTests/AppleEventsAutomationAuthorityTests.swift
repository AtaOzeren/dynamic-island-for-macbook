import AppKit
import Foundation
import Testing

@testable import NotchFlowCore
@testable import NotchFlowProviders

private final class AsyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var isSignalled = false

    func signal() {
        lock.lock()
        isSignalled = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isSignalled {
                lock.unlock()
                continuation.resume()
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func read() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    func read() -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Suite("Apple Events automation authority")
@MainActor
struct AppleEventsAutomationAuthorityTests {
    @Test("running target uses a process identifier Apple Event address")
    func runningTargetUsesProcessIdentifierAddress() {
        let processIdentifier: pid_t = 27_960

        let descriptor = AppleEventsAutomationAuthority.targetDescriptor(
            processIdentifier: processIdentifier
        )

        #expect(descriptor.descriptorType == typeKernelProcessID)
        var expectedProcessIdentifier = processIdentifier
        let expectedData = Data(
            bytes: &expectedProcessIdentifier,
            count: MemoryLayout<pid_t>.size
        )
        #expect(descriptor.data == expectedData)
    }

    @Test("status lookup never blocks the calling actor")
    func statusLookupIsAsynchronous() {
        let queryStarted = DispatchSemaphore(value: 0)
        let releaseQuery = DispatchSemaphore(value: 0)
        let authority = AppleEventsAutomationAuthority { _, askUserIfNeeded in
            #expect(askUserIfNeeded == false)
            queryStarted.signal()
            _ = releaseQuery.wait(timeout: .now() + .milliseconds(250))
            return .granted
        }
        let clock = ContinuousClock()
        let startedAt = clock.now

        let status = authority.status(for: .spotify)
        let elapsed = startedAt.duration(to: clock.now)

        #expect(status == .notDetermined)
        #expect(elapsed < .milliseconds(50))
        #expect(queryStarted.wait(timeout: .now() + .seconds(1)) == .success)
        releaseQuery.signal()
    }

    @Test("status lookup does not call TCC for an app that is not running")
    func stoppedTargetSkipsStatusLookup() {
        let queryStarted = DispatchSemaphore(value: 0)
        let authority = AppleEventsAutomationAuthority(
            determinePermission: { _, _ in
                queryStarted.signal()
                return .granted
            },
            targetEnvironment: .init(
                isRunning: { _ in false },
                prepare: { _ in true }
            )
        )

        #expect(authority.status(for: .spotify) == .notDetermined)
        #expect(queryStarted.wait(timeout: .now() + .milliseconds(50)) == .timedOut)
    }

    @Test("explicit request starts a stopped target before calling TCC")
    func explicitRequestPreparesTarget() async {
        let events = LockedValues<String>()
        let authority = AppleEventsAutomationAuthority(
            determinePermission: { _, askUserIfNeeded in
                #expect(askUserIfNeeded)
                events.append("permission")
                return .granted
            },
            targetEnvironment: .init(
                isRunning: { _ in false },
                prepare: { _ in
                    events.append("launch")
                    return true
                }
            )
        )

        let status = await authority.requestWithoutBlocking(for: .appleMusic)

        #expect(status == .granted)
        #expect(events.read() == ["launch", "permission"])
    }

    @Test("failed target launch ends the request without calling TCC")
    func failedTargetPreparationEndsRequest() async {
        let queryStarted = LockedFlag()
        let authority = AppleEventsAutomationAuthority(
            determinePermission: { _, _ in
                queryStarted.set()
                return .granted
            },
            targetEnvironment: .init(
                isRunning: { _ in false },
                prepare: { _ in false }
            )
        )

        let status = await authority.requestWithoutBlocking(for: .appleMusic)

        #expect(status == .notDetermined)
        #expect(queryStarted.read() == false)
    }

    @Test("TCC status calls never overlap")
    func statusLookupsAreSerialized() {
        let spotifyStarted = DispatchSemaphore(value: 0)
        let releaseSpotify = DispatchSemaphore(value: 0)
        let musicStarted = DispatchSemaphore(value: 0)
        let authority = AppleEventsAutomationAuthority(
            determinePermission: { target, _ in
                switch target {
                case .spotify:
                    spotifyStarted.signal()
                    _ = releaseSpotify.wait(timeout: .now() + .seconds(1))
                case .appleMusic:
                    musicStarted.signal()
                }
                return .notDetermined
            },
            targetEnvironment: .init(
                isRunning: { _ in true },
                prepare: { _ in true }
            )
        )

        _ = authority.status(for: .spotify)
        #expect(spotifyStarted.wait(timeout: .now() + .seconds(1)) == .success)
        _ = authority.status(for: .appleMusic)

        #expect(musicStarted.wait(timeout: .now() + .milliseconds(50)) == .timedOut)
        releaseSpotify.signal()
        #expect(musicStarted.wait(timeout: .now() + .seconds(1)) == .success)
    }

    @Test("explicit permission request does not block the main actor")
    func permissionRequestIsAsynchronous() async {
        let queryStarted = AsyncSignal()
        let releaseQuery = DispatchSemaphore(value: 0)
        let watchdogFired = LockedFlag()
        let authority = AppleEventsAutomationAuthority { _, askUserIfNeeded in
            #expect(askUserIfNeeded)
            queryStarted.signal()
            _ = releaseQuery.wait(timeout: .now() + .seconds(3))
            return .granted
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(2)) {
            watchdogFired.set()
            releaseQuery.signal()
        }

        let request = Task { await authority.requestWithoutBlocking(for: .spotify) }
        await queryStarted.wait()
        let mainActorStayedResponsive = watchdogFired.read() == false
        releaseQuery.signal()

        #expect(mainActorStayedResponsive)
        #expect(await request.value == .granted)
    }
}
