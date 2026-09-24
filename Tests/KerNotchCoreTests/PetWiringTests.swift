import Foundation
import Testing

/// The pet's wiring through the composition root, inspected as source for the
/// reason `CompositionRootWiringTests` gives: no test target can construct the
/// scene the app assembles.
@Suite("Pet wiring")
struct PetWiringTests {
    private static func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    /// The pet keeps the leading flank open, so it widens the pill, the black
    /// surface behind it and the hover target alike — and all three have to be
    /// told. Every sizing function takes the pet without a default, but a
    /// presenter passing `nil` still compiles, so only the wiring can show that
    /// the pet actually reaches each of them.
    @Test("the pet reaches the pill, its surface, its hover target and the Pet tab")
    func petIsWiredThrough() throws {
        let presenter = try Self.source("KerNotch/IslandPresenter.swift")
        let secondary = try Self.source("KerNotch/SecondaryIslandPresentation.swift")
        let app = try Self.source("KerNotch/KerNotchApp.swift")

        // One owner, read by the island that draws it, by the pill that keeps
        // its flank open and by the extent the surface is sized from.
        #expect(presenter.contains("@Published var pet: IslandPetPresentation?"))
        #expect(presenter.contains("IslandPetStage(\n            pet: model.pet,"))
        #expect(presenter.contains("pet: model.pet?.pet\n"))
        #expect(presenter.contains("pet: pet?.pet,"))
        // The hover target, re-read when the pet comes or goes.
        #expect(presenter.contains("pet: { [model] in model.pet?.pet }"))
        #expect(presenter.contains("if narrowsPill || resizesFlank {"))
        // Its routine is carried across refreshes rather than restarted, timed
        // on the clock Core Animation plays it on, and fed what the island
        // shows and what the pointer does.
        #expect(presenter.contains("pet: petKeeper.presentation(\n"))
        #expect(
            presenter.contains(
                "activities: manager.activeActivities,\n                at: ProcessInfo.processInfo.systemUptime"))
        #expect(presenter.contains("onTouch: model.onPetTouched"))
        #expect(presenter.contains("self?.petKeeper.notePetting()"))
        // Seeded from the store and switched live from the Pet tab.
        #expect(presenter.contains("pet = settingsStore.petPreferences.pet"))
        #expect(app.contains("settingsStore.petPreferences = preferences"))
        #expect(app.contains("islandPresenter.applyPetPreferences(preferences)"))
        #expect(app.contains("petPreferences: $petPreferences"))

        // One pet, on the primary island.
        #expect(secondary.contains("pet: nil,"))
        #expect(secondary.contains("pet: { nil }"))
        #expect(!secondary.contains("petRoutines"))

        // The hover peek is undone for the pet, so its art is never resampled.
        #expect(presenter.contains(".environment(\\.islandHoverScale, peekScale)"))
    }

    /// The island's first appearance is at its resting size: content applied
    /// after the panel is ordered in grows it on a spring instead, and with
    /// the pet on that slid the whole island sideways at every launch.
    ///
    /// Matched as the two statements in a row: `start()` also installs
    /// callbacks that refresh, and those sit above `controller.start()`
    /// whether or not the island is filled in first.
    @Test("the island is filled in before its panel is first ordered in")
    func contentPrecedesTheFirstOrderIn() throws {
        let presenter = try Self.source("KerNotch/IslandPresenter.swift")

        #expect(presenter.contains("        refreshContent()\n        controller.start()\n"))
    }
}
