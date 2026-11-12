import AppKit

/// Phase 1 stand-in for the real HUD: a plain non-activating panel that prints
/// kind, level and muted as text. Its only job is to show that the coordinator
/// is driven correctly. Replaced by `HUDPanel` and the style views in Phase 2.
@MainActor
final class PlaceholderHUD {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private static let size = NSSize(width: 460, height: 40)
    private static let topMargin: CGFloat = 12

    private let panel: Panel
    private let label = NSTextField(labelWithString: "")

    init() {
        panel = Panel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let background = NSView(frame: NSRect(origin: .zero, size: Self.size))
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        background.layer?.cornerRadius = 10

        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 12, y: 11, width: Self.size.width - 24, height: 18)
        background.addSubview(label)
        panel.contentView = background
    }

    func apply(_ presentation: HUDPresentation) {
        guard presentation.isVisible, let state = presentation.state else {
            panel.orderOut(nil)
            return
        }
        label.stringValue = Self.text(for: state)
        if let screen = Self.screen(for: presentation.displayID) {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - Self.size.width / 2,
                y: visible.maxY - Self.size.height - Self.topMargin))
        }
        panel.orderFrontRegardless()
    }

    static func text(for state: HUDState) -> String {
        let kind = state.kind == .volume ? "volume" : "brightness"
        let sixteenths = state.level * 16
        var text = String(format: "%@  %.4f (%.2f/16)", kind, state.level, sixteenths)
        if state.kind == .volume { text += "  muted: \(state.isMuted)" }
        if let name = state.deviceName { text += "  \(name)" }
        return text
    }

    /// The display being adjusted, or the screen with keyboard focus.
    private static func screen(for displayID: UInt32?) -> NSScreen? {
        if let displayID {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            let match = NSScreen.screens.first {
                ($0.deviceDescription[key] as? NSNumber)?.uint32Value == displayID
            }
            if let match { return match }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }
}
