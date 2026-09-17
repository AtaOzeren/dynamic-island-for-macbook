import CoreGraphics
import Foundation
import SwiftUI

/// The one grammar every card in the island is drawn to.
///
/// Each kind of card used to carry its own copy of these numbers, and they had
/// drifted apart: a recording glyph was 15pt beside a 24pt agent logo, a track's
/// artwork 40 and a timer's face 44, with three different insets behind them. So
/// the four cards started their text at three different distances from the edge
/// and stood at four different heights, in a panel whose whole point is to read
/// as one list.
///
/// Every per-kind metric now takes its shared values from here, so the cards
/// cannot drift apart again without this one value changing for all of them.
public struct IslandRowGrammar: Equatable, Sendable {
    public static let `default` = IslandRowGrammar()

    /// The box every icon is drawn into, whatever it is: an agent's logo, a
    /// track's artwork, a symbol, or a battery.
    public let iconSize: CGFloat
    /// The gap between a card's edge and what is inside it.
    public let contentInset: CGFloat
    /// The gap between the icon, the text and the trailing control.
    ///
    /// Read against the *widest* icon, not the average one: a monitor or a
    /// battery reaches the edge of its box, so a gap that looked generous
    /// beside a microphone had the screen-recording mark leaning on its label.
    public let columnSpacing: CGFloat
    /// The gap between a card's two lines of text.
    public let textSpacing: CGFloat
    public let controlButtonSize: CGFloat
    public let controlSymbolSize: CGFloat
    public let cornerRadius: CGFloat
    public let width: CGFloat
    public let typeScale: IslandTypeScale

    public init(
        iconSize: CGFloat = 24,
        contentInset: CGFloat = 8,
        columnSpacing: CGFloat = 10,
        textSpacing: CGFloat = 2,
        controlButtonSize: CGFloat = 24,
        controlSymbolSize: CGFloat = 12,
        cornerRadius: CGFloat = 16,
        width: CGFloat = 320,
        typeScale: IslandTypeScale = .default
    ) {
        self.iconSize = iconSize
        self.contentInset = contentInset
        self.columnSpacing = columnSpacing
        self.textSpacing = textSpacing
        self.controlButtonSize = controlButtonSize
        self.controlSymbolSize = controlSymbolSize
        self.cornerRadius = cornerRadius
        self.width = width
        self.typeScale = typeScale
    }

    /// How tall every card is: one icon between two insets. Two lines of text
    /// come to exactly the same height, so a card with a detail line and one
    /// without stand level with each other.
    public var rowHeight: CGFloat {
        contentInset * 2 + max(iconSize, controlButtonSize)
    }

    /// How large a symbol is set inside the icon box.
    ///
    /// Smaller than the box, unlike an app icon or a piece of artwork: a glyph
    /// is drawn with air around it, so a symbol set to the box's own size reads
    /// as bigger than the logo beside it rather than as its equal.
    public var symbolSize: CGFloat { (iconSize * 0.8).rounded() }

    /// A card's headline.
    public var titleSize: CGFloat { typeScale.title }

    /// The line under it.
    public var detailSize: CGFloat { typeScale.detail }

    public func scaled(by factor: CGFloat) -> IslandRowGrammar {
        IslandRowGrammar(
            iconSize: iconSize.grammarScaled(by: factor),
            contentInset: contentInset.grammarScaled(by: factor),
            columnSpacing: columnSpacing.grammarScaled(by: factor),
            textSpacing: textSpacing.grammarScaled(by: factor),
            controlButtonSize: controlButtonSize.grammarScaled(by: factor),
            controlSymbolSize: controlSymbolSize.grammarScaled(by: factor),
            cornerRadius: cornerRadius.grammarScaled(by: factor),
            width: width.grammarScaled(by: factor),
            typeScale: typeScale.scaled(by: factor)
        )
    }
}

extension CGFloat {
    /// Whole points, so a scaled card lands on the same pixel grid the default
    /// one does instead of drawing its hairlines and glyph edges blurred.
    fileprivate func grammarScaled(by factor: CGFloat) -> CGFloat {
        Swift.max((self * factor).rounded(), 1)
    }
}

/// An SF Symbol drawn to a given height rather than set at a point size.
///
/// Symbols do not share proportions: a microphone set at the same point size as
/// a warning triangle draws a fifth taller than it, and both stood beside a
/// 13-point agent logo that is exactly its own size. Fitting each glyph to the
/// band's height is what makes "the same size" true of what is on screen rather
/// than of the number in the code.
struct IslandSymbolIcon: View {
    let systemName: String
    let height: CGFloat

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
    }
}
