import Foundation

/// Where the floating styles (`tahoe`, `circular`) sit on the screen.
enum HUDPosition: String, CaseIterable, Sendable {
    case topRight
    case topLeft
    case topCenter
    case bottomCenter
}

/// The parts of a screen the layout needs, in AppKit screen coordinates
/// (origin bottom-left, y up). A plain value so tests can make one up.
struct ScreenMetrics: Equatable, Sendable {
    var frame: CGRect
    /// The frame minus menu bar and Dock. Equal to `frame` on a screen
    /// without a menu bar.
    var visibleFrame: CGRect
    /// Height of the notch strip, 0 on screens without a notch.
    var safeAreaTop: CGFloat = 0
    /// Widths of the usable strips left and right of the notch
    /// (`NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`); nil on
    /// screens without a notch.
    var auxiliaryTopLeftWidth: CGFloat?
    var auxiliaryTopRightWidth: CGFloat?
}

/// Pure geometry for the HUD panel.
enum HUDLayout {
    /// Gap between the HUD shape and the edge of the usable screen area.
    static let edgeMargin: CGFloat = 10
    /// Transparent canvas around the shape inside the panel: room for the
    /// shadow and for the appear animation.
    static let canvasPadding: CGFloat = 40

    /// The rectangle of the visible shape on the screen.
    static func shapeFrame(
        size: CGSize,
        position: HUDPosition,
        screen: ScreenMetrics,
        margin: CGFloat = edgeMargin
    ) -> CGRect {
        let visible = screen.visibleFrame
        // Below the menu bar when there is one. With the menu bar hidden
        // (full screen) stay below the notch strip instead of straddling it.
        let top = min(visible.maxY, screen.frame.maxY - screen.safeAreaTop)

        let x: CGFloat
        let y: CGFloat
        switch position {
        case .topRight:
            x = visible.maxX - margin - size.width
            y = top - margin - size.height
        case .topLeft:
            x = visible.minX + margin
            y = top - margin - size.height
        case .topCenter:
            x = visible.midX - size.width / 2
            y = top - margin - size.height
        case .bottomCenter:
            x = visible.midX - size.width / 2
            y = visible.minY + margin
        }
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    /// The panel that holds a shape: the shape plus the canvas on every side.
    static func panelFrame(forShape shape: CGRect, padding: CGFloat = canvasPadding) -> CGRect {
        shape.insetBy(dx: -padding, dy: -padding)
    }

    static func panelFrame(
        shapeSize: CGSize,
        position: HUDPosition,
        screen: ScreenMetrics,
        margin: CGFloat = edgeMargin,
        padding: CGFloat = canvasPadding
    ) -> CGRect {
        panelFrame(
            forShape: shapeFrame(size: shapeSize, position: position, screen: screen, margin: margin),
            padding: padding)
    }

    /// Whether a point is on a rounded rectangle. A radius of half the
    /// height (or more) makes it a capsule. Decides which clicks belong to
    /// the HUD and which go to the app underneath.
    static func shape(_ rect: CGRect, cornerRadius: CGFloat, contains point: CGPoint) -> Bool {
        guard rect.width > 0, rect.height > 0,
              point.x >= rect.minX, point.x <= rect.maxX,
              point.y >= rect.minY, point.y <= rect.maxY else { return false }
        let radius = max(0, min(cornerRadius, rect.width / 2, rect.height / 2))
        // Nearest point of the inner rectangle the corner circles sit on.
        let nearestX = min(max(point.x, rect.minX + radius), rect.maxX - radius)
        let nearestY = min(max(point.y, rect.minY + radius), rect.maxY - radius)
        let dx = point.x - nearestX
        let dy = point.y - nearestY
        return dx * dx + dy * dy <= radius * radius
    }
}
