/// How much room the expanded island gives the activities inside it.
///
/// Two tuned layouts rather than a free scale: every card's height feeds the
/// panel's height model and the hover silhouette, and a continuous value would
/// multiply the arrangements that have to be checked for clipping.
public enum IslandSize: String, CaseIterable, Equatable, Sendable {
    /// The compact expanded island KerNotch has always drawn.
    case minimalist
    /// A wider island with larger type, artwork and controls.
    case large

    public var displayName: String {
        switch self {
        case .minimalist: localized("Minimalist")
        case .large: localized("Large")
        }
    }
}
