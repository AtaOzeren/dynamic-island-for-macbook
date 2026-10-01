import Foundation
import Testing

/// KerNotch's own Motion choice has to reach every island's views, inspected
/// as source for the reason `CompositionRootWiringTests` gives. The views read
/// it from the environment and fall back to the system setting without it, so
/// an island that never set it would still compile and still draw — only
/// with every continuous animation ignoring the user.
@Suite("Island motion wiring")
struct IslandMotionWiringTests {
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

    @Test("the Motion choice reaches every island, primary and secondary")
    func motionChoiceReachesEveryIsland() throws {
        let presenter = try Self.source("KerNotch/IslandPresenter.swift")
        let secondary = try Self.source("KerNotch/SecondaryIslandPresentation.swift")

        // Seeded at launch, changed live, and handed to the views.
        #expect(
            presenter.contains(
                "model.reducedMotionOverride = settingsStore.generalPreferences.reducedMotionOverride"
            )
        )
        #expect(presenter.contains("model.reducedMotionOverride = preferenceOverride"))
        #expect(presenter.contains(".environment(\\.islandReducedMotionOverride, model.reducedMotionOverride)"))

        // Every other display, both when it appears and when the choice changes.
        #expect(presenter.contains("secondary.reducedMotionOverride = reduceMotion.preferenceOverride"))
        #expect(presenter.contains("secondary.reducedMotionOverride = preferenceOverride"))
        #expect(secondary.contains("set { model.reducedMotionOverride = newValue }"))
    }
}
