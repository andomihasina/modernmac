import Foundation

/// Pure geometry for the `notch` style, in AppKit screen coordinates
/// (origin bottom-left, y up). Nothing here is hard-coded to a Mac model:
/// the notch comes from the screen's safe area and auxiliary areas.
enum NotchLayout {
    /// How the `notch` style draws on a given screen.
    enum Mode: Equatable, Sendable {
        /// Grows down out of the physical notch, which is at this rectangle.
        case notch(CGRect)
        /// No notch: a floating pill below the top of the screen.
        case pill
    }

    /// The physical notch, or nil on a screen without one.
    ///
    /// `height = safeAreaTop`; `width = frame.width − left − right`, where
    /// left and right are the usable strips beside the notch. The notch
    /// starts where the left strip ends, so an off-centre notch (646 / 645
    /// on Ando's MacBook Air) is placed exactly.
    static func notchRect(in screen: ScreenMetrics) -> CGRect? {
        guard screen.safeAreaTop > 0,
              let left = screen.auxiliaryTopLeftWidth,
              let right = screen.auxiliaryTopRightWidth else { return nil }
        let width = screen.frame.width - left - right
        guard width > 0 else { return nil }
        return CGRect(
            x: screen.frame.minX + left,
            y: screen.frame.maxY - screen.safeAreaTop,
            width: width,
            height: screen.safeAreaTop)
    }

    static func mode(for screen: ScreenMetrics) -> Mode {
        notchRect(in: screen).map(Mode.notch) ?? .pill
    }

    /// The notch grown downward by `dropHeight`: same width, still flush
    /// with the top of the screen.
    static func expandedRect(notch: CGRect, dropHeight: CGFloat) -> CGRect {
        CGRect(
            x: notch.minX, y: notch.minY - dropHeight,
            width: notch.width, height: notch.height + dropHeight)
    }

    /// The fallback pill: centred, `topMargin` below the top of the
    /// usable area (below the menu bar when the screen has one).
    static func pillRect(size: CGSize, screen: ScreenMetrics, topMargin: CGFloat) -> CGRect {
        let visible = screen.visibleFrame
        return CGRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.maxY - topMargin - size.height).rounded(),
            width: size.width,
            height: size.height)
    }

    /// The panel for the notch shape: hangs from the top edge of the screen,
    /// with room at the sides for the top flares and below for the spring's
    /// overshoot.
    static func panelFrame(
        expanded: CGRect, sidePadding: CGFloat, bottomPadding: CGFloat
    ) -> CGRect {
        CGRect(
            x: expanded.minX - sidePadding,
            y: expanded.minY - bottomPadding,
            width: expanded.width + 2 * sidePadding,
            height: expanded.height + bottomPadding)
    }
}
