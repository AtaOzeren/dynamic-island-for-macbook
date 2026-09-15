import CoreAudio
import Foundation
import Testing

@testable import KerNotchProviders

/// The real CoreAudio listeners, against the real HAL.
///
/// The observer's tests run on a fake, and the fake was never the problem: the
/// shipping listeners removed nothing, because Swift hands CoreAudio a new block
/// on every call. Only the driver itself can say whether a removed listener is
/// really gone, so these tests change a property that notifies without touching
/// any device — whether *this process* allows idle sleep during audio IO — and
/// check who hears about it.
///
/// Each check waits for a control listener to hear two changes before looking
/// at the one under test. The second notification is queued behind every
/// delivery the first produced, so nothing that should have fired can still be
/// on its way when the assertion runs.
@Suite("CoreAudioPropertyListeners", .serialized, .enabled(if: SleepingIsAllowedProperty.isSettable))
@MainActor
struct CoreAudioPropertyListenersTests {
    @Test("a listener that was stopped hears nothing")
    func stoppedListenerStaysSilent() async throws {
        let control = CoreAudioPropertyListeners()
        let subject = CoreAudioPropertyListeners()
        let controlCounter = FireCounter()
        let subjectCounter = FireCounter()

        control.listen(to: SleepingIsAllowedProperty.address, on: SleepingIsAllowedProperty.object) {
            controlCounter.record()
        }
        subject.listen(to: SleepingIsAllowedProperty.address, on: SleepingIsAllowedProperty.object) {
            subjectCounter.record()
        }
        subject.stopListening(to: SleepingIsAllowedProperty.address, on: SleepingIsAllowedProperty.object)

        try await Self.toggleTwice(heardBy: controlCounter)

        #expect(subjectCounter.count == 0)
        control.removeAll()
    }

    @Test("listening again to the same property replaces the first listener")
    func listeningAgainReplacesTheListener() async throws {
        let listeners = CoreAudioPropertyListeners()
        let replaced = FireCounter()
        let replacement = FireCounter()

        listeners.listen(to: SleepingIsAllowedProperty.address, on: SleepingIsAllowedProperty.object) {
            replaced.record()
        }
        listeners.listen(to: SleepingIsAllowedProperty.address, on: SleepingIsAllowedProperty.object) {
            replacement.record()
        }

        try await Self.toggleTwice(heardBy: replacement)

        #expect(replaced.count == 0)
        listeners.removeAll()
    }

    @Test("removing every listener silences all of them")
    func removeAllSilencesEveryListener() async throws {
        let control = CoreAudioPropertyListeners()
        let subject = CoreAudioPropertyListeners()
        let controlCounter = FireCounter()
        let subjectCounter = FireCounter()

        control.listen(to: SleepingIsAllowedProperty.address, on: SleepingIsAllowedProperty.object) {
            controlCounter.record()
        }
        subject.listen(to: SleepingIsAllowedProperty.address, on: SleepingIsAllowedProperty.object) {
            subjectCounter.record()
        }
        subject.removeAll()

        try await Self.toggleTwice(heardBy: controlCounter)

        #expect(subjectCounter.count == 0)
        control.removeAll()
    }

    /// Flips the property and back, restoring the process's original value, and
    /// returns once the control listener has heard both changes.
    private static func toggleTwice(heardBy control: FireCounter) async throws {
        let original = try SleepingIsAllowedProperty.read()
        defer { try? SleepingIsAllowedProperty.write(original) }

        try SleepingIsAllowedProperty.write(original == 0 ? 1 : 0)
        #expect(await control.waitUntil(count: 1), "the control listener never heard the first change")

        try SleepingIsAllowedProperty.write(original)
        #expect(await control.waitUntil(count: 2), "the control listener never heard the second change")
    }
}

/// Counts deliveries on the main actor, where the listeners deliver them.
@MainActor
private final class FireCounter {
    private static let pollInterval: Duration = .milliseconds(5)
    private static let timeout: Duration = .seconds(2)

    private(set) var count = 0

    func record() {
        count += 1
    }

    /// Suspends rather than blocks, so the main queue stays free to run the
    /// very deliveries being waited for.
    func waitUntil(count expected: Int) async -> Bool {
        let deadline = ContinuousClock.now + Self.timeout
        while count < expected, ContinuousClock.now < deadline {
            try? await Task.sleep(for: Self.pollInterval)
        }
        return count >= expected
    }
}

/// `kAudioHardwarePropertySleepingIsAllowed`: scoped to the calling process, so
/// changing it notifies listeners without affecting any other app or device.
private enum SleepingIsAllowedProperty {
    struct StatusError: Error {
        let status: OSStatus
    }

    static let object = AudioObjectID(kAudioObjectSystemObject)

    static var address: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertySleepingIsAllowed,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Whether this machine's HAL can run the suite at all; a runner without a
    /// reachable audio server skips it rather than failing it.
    static var isSettable: Bool {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    static func read() throws -> UInt32 {
        var address = address
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr else { throw StatusError(status: status) }
        return value
    }

    static func write(_ value: UInt32) throws {
        var address = address
        var data = value
        let status = AudioObjectSetPropertyData(
            object,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &data
        )
        guard status == noErr else { throw StatusError(status: status) }
    }
}
