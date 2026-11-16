import AppKit
import SwiftUI

/// The one window every HUD style is drawn in (SPEC §5.2). It floats above
/// everything, on every Space and over full-screen apps, and can never take
/// keyboard focus or activate the app.
final class HUDPanel: NSPanel {
    /// Level proven in FINDINGS V6 to draw over the menu bar, for `notch`.
    static let notchLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Mouse events are let in only while the pointer is on the shape.
        ignoresMouseEvents = true
        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit would push a borderless panel out of the menu bar strip.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Hosts the SwiftUI content. The app is never active, so every click on
/// the HUD is a "first mouse" and must be accepted to reach the bar.
final class HUDHostingView<Content: View>: NSHostingView<Content> {
    /// Scrolling over the HUD. Returns true when the HUD used the event.
    var onScroll: ((NSEvent) -> Bool)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        if onScroll?(event) != true { super.scrollWheel(with: event) }
    }
}
