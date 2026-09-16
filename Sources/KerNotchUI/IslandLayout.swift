import CoreGraphics
import KerNotchCore

/// Everything the island size setting changes, resolved in one value.
///
/// The expanded surface is sized in three places — the view that draws it, the
/// controller that hit-tests its silhouette, and the window that has to hold
/// it. Handing all three the same layout is what keeps a large island from
/// being drawn at one size and hovered at another, where the pointer would
/// count as leaving the island while still over its edge.
public struct IslandLayout: Equatable, Sendable {
    public static let minimalist = IslandLayout(panel: .default, items: .default)
    public static let large = IslandLayout(panel: .large, items: .large)

    public let panel: PanelMetrics
    public let items: ExpandedItemMetrics

    public init(panel: PanelMetrics, items: ExpandedItemMetrics) {
        self.panel = panel
        self.items = items
    }

    public init(size: IslandSize) {
        switch size {
        case .minimalist: self = .minimalist
        case .large: self = .large
        }
    }

    /// This layout with its window budget fitted to `screen` — see
    /// `PanelMetrics.fitted(to:)`. Unchanged when there is no screen to fit.
    public func fitted(to screen: ScreenDescription?) -> IslandLayout {
        guard let screen else { return self }
        return IslandLayout(panel: panel.fitted(to: screen), items: items)
    }
}

extension ExpandedItemMetrics {
    /// How much larger every card's type, glyphs, controls and spacing are in
    /// the large island. Paired with `PanelMetrics.large`, whose extra width
    /// grows by more than this, so the bigger cards still gain room around them.
    static let largeScale: CGFloat = 1.2

    /// The `IslandSize.large` budget: the default metrics, scaled as one.
    ///
    /// Derived rather than written out so the two sizes cannot drift apart in
    /// proportion — a card that is tuned in one stays tuned in the other.
    public static let large = ExpandedItemMetrics.default.scaled(by: largeScale)

    func scaled(by factor: CGFloat) -> ExpandedItemMetrics {
        ExpandedItemMetrics(
            panel: panel.scaled(by: factor),
            music: music.scaled(by: factor),
            timer: timer.scaled(by: factor),
            aiAgent: aiAgent.scaled(by: factor),
            typeScale: typeScale.scaled(by: factor)
        )
    }
}

extension CGFloat {
    /// Whole points, so a scaled card lands on the same pixel grid the default
    /// one does instead of drawing its hairlines and glyph edges blurred.
    fileprivate func islandScaled(by factor: CGFloat) -> CGFloat {
        Swift.max((self * factor).rounded(), 1)
    }
}

extension IslandTypeScale {
    func scaled(by factor: CGFloat) -> IslandTypeScale {
        IslandTypeScale(
            title: title.islandScaled(by: factor),
            detail: detail.islandScaled(by: factor),
            nestedTitle: nestedTitle.islandScaled(by: factor),
            nestedDetail: nestedDetail.islandScaled(by: factor),
            footnote: footnote.islandScaled(by: factor)
        )
    }
}

extension ExpandedPanelMetrics {
    func scaled(by factor: CGFloat) -> ExpandedPanelMetrics {
        ExpandedPanelMetrics(
            rowHeight: rowHeight.islandScaled(by: factor),
            rowSpacing: rowSpacing.islandScaled(by: factor),
            columnSpacing: columnSpacing.islandScaled(by: factor),
            contentInset: contentInset.islandScaled(by: factor),
            symbolSize: symbolSize.islandScaled(by: factor),
            symbolColumnWidth: symbolColumnWidth.islandScaled(by: factor),
            titleSize: titleSize.islandScaled(by: factor),
            detailSize: detailSize.islandScaled(by: factor),
            cornerRadius: cornerRadius.islandScaled(by: factor),
            width: width.islandScaled(by: factor)
        )
    }
}

extension MusicViewMetrics {
    func scaled(by factor: CGFloat) -> MusicViewMetrics {
        MusicViewMetrics(
            artworkSize: artworkSize.islandScaled(by: factor),
            contentInset: contentInset.islandScaled(by: factor),
            textSpacing: textSpacing.islandScaled(by: factor),
            columnSpacing: columnSpacing.islandScaled(by: factor),
            titleSize: titleSize.islandScaled(by: factor),
            subtitleSize: subtitleSize.islandScaled(by: factor),
            transportSymbolSize: transportSymbolSize.islandScaled(by: factor),
            transportButtonSize: transportButtonSize.islandScaled(by: factor),
            transportSpacing: transportSpacing.islandScaled(by: factor),
            cornerRadius: cornerRadius.islandScaled(by: factor),
            width: width.islandScaled(by: factor)
        )
    }
}

extension TimerViewMetrics {
    func scaled(by factor: CGFloat) -> TimerViewMetrics {
        TimerViewMetrics(
            glyphSize: glyphSize.islandScaled(by: factor),
            contentInset: contentInset.islandScaled(by: factor),
            textSpacing: textSpacing.islandScaled(by: factor),
            columnSpacing: columnSpacing.islandScaled(by: factor),
            timeSize: timeSize.islandScaled(by: factor),
            titleSize: titleSize.islandScaled(by: factor),
            controlSymbolSize: controlSymbolSize.islandScaled(by: factor),
            controlButtonSize: controlButtonSize.islandScaled(by: factor),
            controlSpacing: controlSpacing.islandScaled(by: factor),
            cornerRadius: cornerRadius.islandScaled(by: factor),
            width: width.islandScaled(by: factor)
        )
    }
}

extension AIAgentViewMetrics {
    func scaled(by factor: CGFloat) -> AIAgentViewMetrics {
        AIAgentViewMetrics(
            glyphSize: glyphSize.islandScaled(by: factor),
            contentInset: contentInset.islandScaled(by: factor),
            textSpacing: textSpacing.islandScaled(by: factor),
            columnSpacing: columnSpacing.islandScaled(by: factor),
            titleSize: titleSize.islandScaled(by: factor),
            detailSize: detailSize.islandScaled(by: factor),
            progressBarHeight: progressBarHeight.islandScaled(by: factor),
            cornerRadius: cornerRadius.islandScaled(by: factor),
            width: width.islandScaled(by: factor),
            subagentRowHeight: subagentRowHeight.islandScaled(by: factor),
            subagentSeparatorHeight: subagentSeparatorHeight.islandScaled(by: factor),
            subagentNameSize: subagentNameSize.islandScaled(by: factor),
            subagentDetailSize: subagentDetailSize.islandScaled(by: factor),
            disclosureControlHeight: disclosureControlHeight.islandScaled(by: factor)
        )
    }
}
