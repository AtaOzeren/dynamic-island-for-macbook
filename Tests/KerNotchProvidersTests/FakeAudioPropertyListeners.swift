import CoreAudio

@testable import KerNotchProviders

/// CoreAudio's subscription surface, faked: registrations are recorded so the
/// test can assert what is being watched, and fired on demand so nothing waits
/// on a driver.
///
/// It also counts how often each listener was registered. The fake replaces by
/// key just as the real listeners now do, so the active set alone could never
/// show the observer re-registering on every change — which is exactly how the
/// runaway went unnoticed while every test here passed.
@MainActor
final class FakeAudioPropertyListeners: AudioPropertyListening {
    private struct Key: Hashable {
        let property: AudioProperty
        let object: AudioObjectID
    }

    private var blocks: [Key: @MainActor () -> Void] = [:]
    private var registrationCounts: [Key: Int] = [:]

    /// Objects whose listeners the driver refuses to register.
    var refusedObjects: Set<AudioObjectID> = []

    var count: Int { blocks.count }
    var isEmpty: Bool { blocks.isEmpty }

    func listen(
        to property: AudioProperty,
        on object: AudioObjectID,
        changed: @escaping @MainActor () -> Void
    ) -> Bool {
        let key = Key(property: property, object: object)
        registrationCounts[key, default: 0] += 1
        guard refusedObjects.contains(object) == false else { return false }
        blocks[key] = changed
        return true
    }

    func stopListening(to property: AudioProperty, on object: AudioObjectID) {
        blocks[Key(property: property, object: object)] = nil
    }

    func removeAll() {
        blocks.removeAll()
    }

    func isListening(to property: AudioProperty, on object: AudioObjectID) -> Bool {
        blocks[Key(property: property, object: object)] != nil
    }

    func listenedObjects(for property: AudioProperty) -> Set<AudioObjectID> {
        Set(blocks.keys.filter { $0.property == property }.map(\.object))
    }

    func registrationCount(for property: AudioProperty, on object: AudioObjectID) -> Int {
        registrationCounts[Key(property: property, object: object)] ?? 0
    }

    func fire(_ property: AudioProperty, on object: AudioObjectID) {
        blocks[Key(property: property, object: object)]?()
    }
}
