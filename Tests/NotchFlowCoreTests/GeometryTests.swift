import CoreGraphics
import Testing

@testable import NotchFlowCore

@Suite("Geometry")
struct GeometryTests {
    @Test("computes the 14-inch MacBook Pro notch rectangle")
    func fourteenInchMacBookPro() {
        let screen = ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            safeAreaInsets: ScreenSafeAreaInsets(top: 37),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 719, height: 37),
            auxiliaryTopRightArea: CGRect(x: 793, y: 945, width: 719, height: 37),
            isBuiltIn: true
        )

        let rect = notchRect(for: screen)
        #expect(rect?.origin.x == 719)
        #expect(rect?.origin.y == 945)
        #expect(rect?.width == 74)
        #expect(rect?.height == 37)
        #expect(isNotchedBuiltInDisplay(screen))
    }

    @Test("computes the 16-inch MacBook Pro notch rectangle")
    func sixteenInchMacBookPro() {
        let screen = ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
            safeAreaInsets: ScreenSafeAreaInsets(top: 37),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 1_080, width: 827, height: 37),
            auxiliaryTopRightArea: CGRect(x: 901, y: 1_080, width: 827, height: 37),
            isBuiltIn: true
        )

        let rect = notchRect(for: screen)
        #expect(rect?.origin.x == 827)
        #expect(rect?.origin.y == 1_080)
        #expect(rect?.width == 74)
        #expect(rect?.height == 37)
        #expect(isNotchedBuiltInDisplay(screen))
    }

    @Test("computes a notched MacBook Air rectangle")
    func notchedMacBookAir() {
        let screen = ScreenDescription(
            frame: CGRect(x: 120, y: 80, width: 1_470, height: 956),
            safeAreaInsets: ScreenSafeAreaInsets(top: 32),
            auxiliaryTopLeftArea: CGRect(x: 120, y: 1_004, width: 699, height: 32),
            auxiliaryTopRightArea: CGRect(x: 891, y: 1_004, width: 699, height: 32),
            isBuiltIn: true
        )

        let rect = notchRect(for: screen)
        #expect(rect?.origin.x == 819)
        #expect(rect?.origin.y == 1_004)
        #expect(rect?.width == 72)
        #expect(rect?.height == 32)
        #expect(isNotchedBuiltInDisplay(screen))
    }

    @Test("rejects a built-in Mac without a notch")
    func nonNotchedMac() {
        let screen = ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            safeAreaInsets: .zero,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            isBuiltIn: true
        )

        #expect(notchRect(for: screen) == nil)
        #expect(!isNotchedBuiltInDisplay(screen))
    }

    @Test("rejects a zero-inset external display")
    func zeroInsetExternalDisplay() {
        let screen = ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 2_560, height: 1_440),
            safeAreaInsets: .zero,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            isBuiltIn: false
        )

        #expect(notchRect(for: screen) == nil)
        #expect(!isNotchedBuiltInDisplay(screen))
    }

    @Test("requires the display to be built in")
    func externalDisplayWithTopInset() {
        let screen = ScreenDescription(
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            safeAreaInsets: ScreenSafeAreaInsets(top: 37),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 719, height: 37),
            auxiliaryTopRightArea: CGRect(x: 793, y: 945, width: 719, height: 37),
            isBuiltIn: false
        )

        #expect(!isNotchedBuiltInDisplay(screen))
    }

    @Test("returns nil when either auxiliary area is missing")
    func missingAuxiliaryAreas() {
        let frame = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let insets = ScreenSafeAreaInsets(top: 37)
        let leftArea = CGRect(x: 0, y: 945, width: 719, height: 37)
        let rightArea = CGRect(x: 793, y: 945, width: 719, height: 37)

        #expect(
            notchRect(
                frame: frame,
                safeAreaInsets: insets,
                auxiliaryTopLeftArea: nil,
                auxiliaryTopRightArea: rightArea
            ) == nil)
        #expect(
            notchRect(
                frame: frame,
                safeAreaInsets: insets,
                auxiliaryTopLeftArea: leftArea,
                auxiliaryTopRightArea: nil
            ) == nil)
    }

    @Test("returns nil for empty auxiliary areas")
    func emptyAuxiliaryAreas() {
        let frame = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let insets = ScreenSafeAreaInsets(top: 37)
        let validArea = CGRect(x: 793, y: 945, width: 719, height: 37)

        #expect(
            notchRect(
                frame: frame,
                safeAreaInsets: insets,
                auxiliaryTopLeftArea: .zero,
                auxiliaryTopRightArea: validArea
            ) == nil)
        #expect(
            notchRect(
                frame: frame,
                safeAreaInsets: insets,
                auxiliaryTopLeftArea: validArea,
                auxiliaryTopRightArea: CGRect(x: 1_512, y: 945, width: 0, height: 37)
            ) == nil)
    }

    @Test("returns nil for degenerate geometry")
    func degenerateGeometry() {
        let insets = ScreenSafeAreaInsets(top: 37)

        #expect(
            notchRect(
                frame: .zero,
                safeAreaInsets: insets,
                auxiliaryTopLeftArea: CGRect(x: 0, y: 0, width: 719, height: 37),
                auxiliaryTopRightArea: CGRect(x: 793, y: 0, width: 719, height: 37)
            ) == nil)
        #expect(
            notchRect(
                frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
                safeAreaInsets: insets,
                auxiliaryTopLeftArea: CGRect(x: 0, y: 945, width: 800, height: 37),
                auxiliaryTopRightArea: CGRect(x: 793, y: 945, width: 719, height: 37)
            ) == nil)
    }

    @Test("a frame is only usable for presentation when it describes real pixels")
    func usableForPresentationRequiresARealFrame() {
        let validScreen = ScreenDescription(
            frame: CGRect(x: -1_800, y: 0, width: 2_560, height: 1_440),
            safeAreaInsets: .zero,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            isBuiltIn: false
        )
        let zeroWidth = validScreen.withFrame(CGRect(x: 0, y: 0, width: 0, height: 1_440))
        let zeroHeight = validScreen.withFrame(CGRect(x: 0, y: 0, width: 2_560, height: 0))
        let infinite = validScreen.withFrame(
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: CGFloat.infinity)
        )
        let nullFrame = validScreen.withFrame(.null)

        #expect(validScreen.isUsableForPresentation)
        #expect(!zeroWidth.isUsableForPresentation)
        #expect(!zeroHeight.isUsableForPresentation)
        #expect(!infinite.isUsableForPresentation)
        #expect(!nullFrame.isUsableForPresentation)
    }
}

private extension ScreenDescription {
    func withFrame(_ frame: CGRect) -> ScreenDescription {
        ScreenDescription(
            frame: frame,
            safeAreaInsets: safeAreaInsets,
            auxiliaryTopLeftArea: auxiliaryTopLeftArea,
            auxiliaryTopRightArea: auxiliaryTopRightArea,
            isBuiltIn: isBuiltIn
        )
    }
}
