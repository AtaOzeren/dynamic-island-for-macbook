import CoreAudio
import Foundation
import os

/// Real CoreAudio property listeners, registered on the main queue and torn
/// down by the exact pair that registered them.
///
/// Built on the function-pointer API rather than the block API on purpose.
/// Swift re-bridges a closure into a brand-new block every time one is passed
/// to CoreAudio, so `AudioObjectRemovePropertyListenerBlock` never finds the
/// block that was added: it returns `noErr` and the listener stays. The
/// recording observer re-subscribed on every device-list change, so each
/// display change or wake doubled its listeners until the main thread did
/// nothing else — every CPU watchdog alarm sample shows that stack. A C
/// function and an integer client datum compare by value, so removal removes.
///
/// One registration per object and property address: listening again replaces
/// the earlier listener instead of stacking a second one beside it.
@MainActor
final class CoreAudioPropertyListeners: AudioPropertyListening {
    private static let logger = Logger(
        subsystem: "com.kernotch.KerNotch",
        category: "coreaudio-listeners"
    )

    private struct Key: Hashable {
        let object: AudioObjectID
        let selector: AudioObjectPropertySelector
        let scope: AudioObjectPropertyScope
        let element: AudioObjectPropertyElement

        init(object: AudioObjectID, address: AudioObjectPropertyAddress) {
            self.object = object
            selector = address.mSelector
            scope = address.mScope
            element = address.mElement
        }
    }

    private struct Registration {
        let object: AudioObjectID
        let address: AudioObjectPropertyAddress
        let token: CoreAudioListenerToken
    }

    private var registrations: [Key: Registration] = [:]

    @discardableResult
    func listen(
        to property: AudioProperty,
        on object: AudioObjectID,
        changed: @escaping @MainActor () -> Void
    ) -> Bool {
        listen(to: property.address, on: object, changed: changed)
    }

    func stopListening(to property: AudioProperty, on object: AudioObjectID) {
        stopListening(to: property.address, on: object)
    }

    /// The address-level form, so a test can observe a property it is able to
    /// change without touching any device.
    @discardableResult
    func listen(
        to address: AudioObjectPropertyAddress,
        on object: AudioObjectID,
        changed: @escaping @MainActor () -> Void
    ) -> Bool {
        stopListening(to: address, on: object)

        let token = CoreAudioListenerRegistry.register(changed)
        var registeredAddress = address
        let status = AudioObjectAddPropertyListener(
            object,
            &registeredAddress,
            coreAudioPropertyDidChange,
            token.clientData
        )

        guard status == noErr else {
            CoreAudioListenerRegistry.unregister(token)
            Self.logger.error(
                "Adding a listener for selector \(address.mSelector, privacy: .public) on object \(object, privacy: .public) failed with status \(status, privacy: .public)"
            )
            return false
        }

        registrations[Key(object: object, address: address)] = Registration(
            object: object,
            address: address,
            token: token
        )
        return true
    }

    func stopListening(to address: AudioObjectPropertyAddress, on object: AudioObjectID) {
        guard let registration = registrations.removeValue(forKey: Key(object: object, address: address)) else {
            return
        }
        remove(registration)
    }

    func removeAll() {
        let removed = Array(registrations.values)
        registrations.removeAll()
        for registration in removed {
            remove(registration)
        }
    }

    /// A device that has already gone answers removal with a bad-object error,
    /// which is expected. Any other failure is logged: removal that silently
    /// left listeners attached is exactly how the CPU runaway began.
    private func remove(_ registration: Registration) {
        var address = registration.address
        let status = AudioObjectRemovePropertyListener(
            registration.object,
            &address,
            coreAudioPropertyDidChange,
            registration.token.clientData
        )
        CoreAudioListenerRegistry.unregister(registration.token)

        guard status != noErr, status != kAudioHardwareBadObjectError else { return }
        Self.logger.error(
            "Removing a listener for selector \(address.mSelector, privacy: .public) on object \(registration.object, privacy: .public) failed with status \(status, privacy: .public)"
        )
    }

    deinit {
        MainActor.assumeIsolated { removeAll() }
    }
}

/// The client datum CoreAudio hands back to the listener function.
///
/// An integer rather than a pointer to the owning object: the HAL can be in
/// the middle of a callback on its own thread while the main thread removes the
/// listener, and a late delivery of a token that is no longer registered does
/// nothing, where a pointer to a released object would be read after free.
private struct CoreAudioListenerToken: Hashable, Sendable {
    let rawValue: UInt

    var clientData: UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: rawValue)
    }
}

/// Maps tokens back to the handlers they were registered for.
@MainActor
private enum CoreAudioListenerRegistry {
    private static var handlers: [CoreAudioListenerToken: @MainActor () -> Void] = [:]

    /// Starts at zero and is incremented before use, so no token ever carries a
    /// null client datum and no token is ever reused.
    private static var lastRawValue: UInt = 0

    static func register(_ handler: @escaping @MainActor () -> Void) -> CoreAudioListenerToken {
        lastRawValue += 1
        let token = CoreAudioListenerToken(rawValue: lastRawValue)
        handlers[token] = handler
        return token
    }

    static func unregister(_ token: CoreAudioListenerToken) {
        handlers[token] = nil
    }

    static func deliver(_ token: CoreAudioListenerToken) {
        guard let handler = handlers[token] else { return }
        handler()
    }
}

/// Called by the HAL on its own notification thread. Converts the client datum
/// to a token before hopping, so nothing thread-unsafe crosses to the main
/// queue, and never calls back into CoreAudio from here.
private func coreAudioPropertyDidChange(
    _ object: AudioObjectID,
    _ addressCount: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    let token = CoreAudioListenerToken(rawValue: UInt(bitPattern: clientData))
    DispatchQueue.main.async {
        MainActor.assumeIsolated { CoreAudioListenerRegistry.deliver(token) }
    }
    return noErr
}
