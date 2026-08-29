import CoreGraphics

public struct ScreenSafeAreaInsets: Equatable, Sendable {
    public static let zero = ScreenSafeAreaInsets(top: 0)

    public let top: CGFloat

    public init(top: CGFloat) {
        self.top = top
    }
}

public struct ScreenDescription: Sendable {
    public let frame: CGRect
    public let safeAreaInsets: ScreenSafeAreaInsets
    public let auxiliaryTopLeftArea: CGRect?
    public let auxiliaryTopRightArea: CGRect?
    public let isBuiltIn: Bool

    public init(
        frame: CGRect,
        safeAreaInsets: ScreenSafeAreaInsets,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?,
        isBuiltIn: Bool
    ) {
        self.frame = frame
        self.safeAreaInsets = safeAreaInsets
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.isBuiltIn = isBuiltIn
    }
}

public func notchRect(
    frame: CGRect,
    safeAreaInsets: ScreenSafeAreaInsets,
    auxiliaryTopLeftArea: CGRect?,
    auxiliaryTopRightArea: CGRect?
) -> CGRect? {
    guard isValid(rect: frame),
          safeAreaInsets.top.isFinite,
          safeAreaInsets.top > 0,
          safeAreaInsets.top <= frame.height,
          let auxiliaryTopLeftArea,
          let auxiliaryTopRightArea,
          isValid(rect: auxiliaryTopLeftArea),
          isValid(rect: auxiliaryTopRightArea),
          frame.contains(auxiliaryTopLeftArea),
          frame.contains(auxiliaryTopRightArea),
          auxiliaryTopLeftArea.maxX < auxiliaryTopRightArea.minX
    else {
        return nil
    }

    let rect = CGRect(
        x: auxiliaryTopLeftArea.maxX,
        y: frame.maxY - safeAreaInsets.top,
        width: auxiliaryTopRightArea.minX - auxiliaryTopLeftArea.maxX,
        height: safeAreaInsets.top
    )

    guard isValid(rect: rect), frame.contains(rect) else {
        return nil
    }

    return rect
}

public func notchRect(for screen: ScreenDescription) -> CGRect? {
    notchRect(
        frame: screen.frame,
        safeAreaInsets: screen.safeAreaInsets,
        auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
        auxiliaryTopRightArea: screen.auxiliaryTopRightArea
    )
}

public func isNotchedBuiltInDisplay(_ screen: ScreenDescription) -> Bool {
    screen.isBuiltIn && screen.safeAreaInsets.top.isFinite && screen.safeAreaInsets.top > 0
}

private func isValid(rect: CGRect) -> Bool {
    !rect.isNull
    && !rect.isInfinite
    && rect.width > 0
    && rect.height > 0
    && rect.origin.x.isFinite
    && rect.origin.y.isFinite
    && rect.width.isFinite
    && rect.height.isFinite
}
