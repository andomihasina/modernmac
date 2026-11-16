import AppKit

extension NSScreen {
    /// The `CGDirectDisplayID` behind this screen.
    var displayID: UInt32? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// The values the HUD layout works from.
    var metrics: ScreenMetrics {
        ScreenMetrics(
            frame: frame,
            visibleFrame: visibleFrame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryTopLeftWidth: auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: auxiliaryTopRightArea?.width)
    }

    /// The physical notch in screen coordinates, computed from the safe
    /// area and the auxiliary areas; nil on screens without a notch.
    var notchRect: CGRect? {
        NotchLayout.notchRect(in: metrics)
    }

    static func screen(forDisplayID displayID: UInt32) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }

    static var underPointer: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }

    /// Where a HUD goes (SPEC §5.1): the display being adjusted when the
    /// event names one (brightness), otherwise the screen with keyboard
    /// focus, falling back to the screen under the pointer.
    static func hudTarget(displayID: UInt32?) -> NSScreen? {
        if let displayID, let match = screen(forDisplayID: displayID) { return match }
        return main ?? underPointer ?? screens.first
    }
}
