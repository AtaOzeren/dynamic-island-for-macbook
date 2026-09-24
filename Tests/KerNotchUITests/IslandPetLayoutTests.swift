import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import KerNotchCore
@testable import KerNotchUI

/// Where the pet lives on the compact pill, and how that shapes the pill.
@Suite("Island pet layout")
@MainActor
struct IslandPetLayoutTests {
    private struct StubActivity: Activity {
        let identity: ActivityIdentity
        let kind: ActivityKind
        let priority: ActivityPriority
        let compactRank: CompactRank
    }

    private static let notch = CGSize(width: 185, height: 32)

    private static let standardKinds: [(ActivityKind, CompactRank)] = [
        (.recording, .capture),
        (.discordCall, .call),
        (.charging, .transition),
        (.timer, .tracking),
        (.music, .ambient),
    ]

    /// `standardCount` icons that are not agents, and `agentCount` agents.
    private static func presentation(standardCount: Int, agentCount: Int = 0) -> CompactActivityPresentation {
        let manager = ActivityManager()
        for index in 0..<standardCount {
            let (kind, rank) = standardKinds[index]
            manager.register(
                StubActivity(
                    identity: ActivityIdentity("standard.\(index)"),
                    kind: kind,
                    priority: .normal,
                    compactRank: rank
                ),
                at: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        for agent in IPCAgentID.allCases.prefix(agentCount) {
            manager.register(AIAgentActivity(agent: agent, sessionID: UUID(), state: .working, detail: "Working"))
        }
        return manager.compactPresentation
    }

    private static func layout(standardCount: Int, agentCount: Int = 0, pet: IslandPet?) -> CompactSlotLayout {
        compactSlotLayout(
            for: presentation(standardCount: standardCount, agentCount: agentCount),
            hiding: [],
            housing: pet
        )
    }

    @Test("an empty flank is the pet's to roam")
    func emptyFlankIsRoamed() {
        let layout = Self.layout(standardCount: 0, pet: .shiba)

        #expect(layout.petStage == .roaming)
        #expect(layout.leading.isEmpty)
        #expect(layout.leadingPlaceCount == CompactFlankAllocation.slotsPerSide)
    }

    @Test(
        "the pet sits beside one icon and leaves when the flank is full",
        arguments: [
            (1, 0, PetStage.resting),
            (2, 0, .resting),
            (3, 0, .away),
            (4, 0, .away),
            (1, 1, .resting),
            (2, 2, .away),
        ]
    )
    func iconsDecideWhereThePetGoes(standardCount: Int, agentCount: Int, stage: PetStage) {
        #expect(Self.layout(standardCount: standardCount, agentCount: agentCount, pet: .shiba).petStage == stage)
    }

    /// The user's rule: icons are placed exactly as they always were, and the
    /// pet makes do with what is left.
    @Test("a pet never moves an icon", arguments: 0...5)
    func petNeverMovesAnIcon(standardCount: Int) {
        for agentCount in 0...2 {
            let withPet = Self.layout(standardCount: standardCount, agentCount: agentCount, pet: .shiba)
            let without = Self.layout(standardCount: standardCount, agentCount: agentCount, pet: nil)

            #expect(withPet.leading == without.leading)
            #expect(withPet.trailing == without.trailing)
        }
    }

    @Test("without a pet there is no stage and the flank is as wide as its icons")
    func noPetNoStage() {
        let layout = Self.layout(standardCount: 1, pet: nil)

        #expect(layout.petStage == nil)
        #expect(layout.leadingPlaceCount == layout.leading.count)
    }

    /// An icon arriving beside the pet takes the pet's place, not new room, so
    /// the island does not twitch wider under it.
    @Test("the pill keeps one width as an icon comes and goes beside the pet")
    func pillKeepsItsWidthBesideThePet() {
        let empty = compactPillSize(for: Self.layout(standardCount: 0, pet: .shiba), notchSize: Self.notch)
        let oneIcon = compactPillSize(for: Self.layout(standardCount: 1, pet: .shiba), notchSize: Self.notch)

        #expect(empty == oneIcon)
    }

    @Test("the pet widens the empty island by one full flank and its gap")
    func petWidensTheEmptyIsland() {
        let without = compactPillSize(for: Self.layout(standardCount: 0, pet: nil), notchSize: Self.notch)
        let with = compactPillSize(for: Self.layout(standardCount: 0, pet: .shiba), notchSize: Self.notch)
        let flank = compactSideWidth(slotCount: CompactFlankAllocation.slotsPerSide, metrics: .default)

        #expect(with.width - without.width == flank + CompactPillMetrics.default.slotSpacing)
        #expect(with.height == without.height)
    }

    @Test("the island's surface grows when the pet arrives")
    func surfaceGrowsWithThePet() {
        func input(pet: IslandPet?) -> IslandExtentInput {
            IslandExtentInput(
                state: .compact,
                compact: Self.presentation(standardCount: 0),
                hiddenMusicSlotIDs: [],
                pet: pet,
                expanded: [],
                disclosedInstances: [],
                registrationTimes: [:],
                notchSize: Self.notch,
                layout: .minimalist
            )
        }

        #expect(
            islandExtentChange(
                from: islandSurfaceSize(input(pet: nil)),
                to: islandSurfaceSize(input(pet: .shiba))
            ) == .growing
        )
        #expect(islandCompactSlotLayout(input(pet: .shiba)).leadingPlaceCount == CompactFlankAllocation.slotsPerSide)
    }
}

/// The pointer over the pet is the pointer over the island.
@Suite("Island pet hover", .serialized)
@MainActor
struct IslandPetHoverTests {
    private static let metrics = PanelMetrics(
        maximumExpandedSize: CGSize(width: 640, height: 260),
        minimumBottomInset: 120
    )

    private static let notchedScreen = ScreenDescription(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaInsets: ScreenSafeAreaInsets(top: 37),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 656, height: 37),
        auxiliaryTopRightArea: CGRect(x: 856, y: 945, width: 656, height: 37),
        isBuiltIn: true
    )

    @MainActor
    private final class PetBox {
        var pet: IslandPet? = .shiba
    }

    @MainActor
    private final class Mouse: MouseLocationObserving {
        private var observer: MouseLocationObserver?

        func startObserving(_ observer: @escaping MouseLocationObserver) {
            self.observer = observer
        }

        func stopObserving() {
            observer = nil
        }

        func move(to location: CGPoint) {
            observer?(location)
        }
    }

    private struct StillMotion: ReduceMotionQuerying {
        let prefersReducedMotion = false
    }

    @Test("the pet's flank takes the pointer, and stops the moment the pet is switched off")
    func hoverFollowsThePet() throws {
        let box = PetBox()
        let mouse = Mouse()
        let controller = PresentationController(
            panel: NotchPanel(metrics: Self.metrics, content: Color.clear),
            manager: ActivityManager(),
            layout: IslandLayout(panel: Self.metrics, items: .default),
            mouse: mouse,
            reduceMotion: StillMotion(),
            screen: { Self.notchedScreen },
            pet: { box.pet }
        )
        controller.start()

        let withPet = compactHitRect(
            for: Self.notchedScreen,
            leadingSlotCount: CompactFlankAllocation.slotsPerSide,
            trailingSlotCount: 0,
            metrics: Self.metrics
        )
        let bare = compactHitRect(for: Self.notchedScreen, slotCount: 0, metrics: Self.metrics)
        let overThePet = CGPoint(x: withPet.minX + 2, y: withPet.midY)
        try #require(bare.contains(overThePet) == false)

        mouse.move(to: overThePet)
        #expect(controller.isHovered)

        box.pet = nil
        controller.compactLayoutDidChange()

        #expect(controller.isHovered == false)
    }
}
