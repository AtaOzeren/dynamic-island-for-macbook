import KerNotchCore
import SwiftUI

/// The Pet pane: whether a pet lives on the island and which one, with the
/// pet itself walking beside the switch.
///
/// Like every other pane it owns no preference state — it edits the binding
/// the composition root hands it.
public struct PetSettingsView: View {
    /// The preview strip's height: a compact island's, so the pet is shown at
    /// the size it is drawn on the notch.
    private static let previewHeight: CGFloat = 32

    @Binding private var preferences: PetPreferences
    private let metrics: SettingsPaneMetrics

    /// When the pane appeared, in uptime, which is when the preview's pet
    /// walked in.
    @State private var previewStartedAt = ProcessInfo.processInfo.systemUptime

    public init(preferences: Binding<PetPreferences>, metrics: SettingsPaneMetrics = .default) {
        self._preferences = preferences
        self.metrics = metrics
    }

    public var isEnabled: Binding<Bool> {
        Binding(
            get: { preferences.isEnabled },
            set: { preferences.isEnabled = $0 }
        )
    }

    public var species: Binding<PetSpecies> {
        Binding(
            get: { preferences.species },
            set: { preferences.species = $0 }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            SettingsSection(
                title: localized("Island pet"),
                caption: localized(
                    "A small pixel pet lives on the island's left side. It steps aside for an activity and leaves when no room is left."
                ),
                metrics: metrics
            ) {
                Toggle(localized("Show the pet on the island"), isOn: isEnabled)
                Picker(localized("Animal"), selection: species) {
                    ForEach(PetSpecies.allCases, id: \.self) { species in
                        Text(species.displayName).tag(species)
                    }
                }
                .pickerStyle(.segmented)
                preview
                Text(localized("The pet sits still while motion is reduced."))
                    .font(.system(size: metrics.footnoteSize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .settingsPaneFrame(metrics)
        .onChange(of: preferences.species) {
            previewStartedAt = ProcessInfo.processInfo.systemUptime
        }
    }

    /// The chosen pet on a strip of the island's black, walking in and then
    /// the routine it walks on an empty flank — afresh whenever the choice
    /// changes. Dimmed while switched off: it is what the switch would add,
    /// not something already on the island.
    private var preview: some View {
        let pet = IslandPet(species: preferences.species)
        let geometry = pet.stageGeometry()
        let routine = PetRoutine(
            stage: .roaming,
            from: PetPose(position: geometry.offstagePosition, facing: .right, frame: .stand),
            geometry: geometry,
            species: pet.species
        )
        return IslandPetView(
            presentation: IslandPetPresentation(
                pet: pet,
                performance: PetPerformance(routine: routine, startedAt: previewStartedAt)
            ),
            placement: PetPlacement(pet: pet, pillHeight: Self.previewHeight, metrics: .default)
        )
        .padding(.trailing, CGFloat(geometry.edgeInset))
        .background(
            Color.black,
            in: RoundedRectangle(cornerRadius: Self.previewHeight / 2, style: .continuous)
        )
        .opacity(preferences.isEnabled ? 1 : 0.5)
        .accessibilityHidden(true)
    }
}
