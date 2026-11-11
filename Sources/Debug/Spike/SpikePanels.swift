#if DEBUG
import AppKit
import SwiftUI

/// Borderless, transparent, non-activating panel used by the spike's visual tests.
final class SpikePanel: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // AppKit must not push the panel below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
enum SpikePanels {
    // MARK: - Experiment 3: blur test panel (V5)

    private static let capsuleSize = NSSize(width: 280, height: 44)
    private static let margin: CGFloat = 20
    private static let labelHeight: CGFloat = 18

    /// Three capsules side by side:
    ///   A  NSVisualEffectView, behind-window, clipped with `maskImage`
    ///   B  NSVisualEffectView, behind-window, clipped with a layer corner radius
    ///   C  SwiftUI `Material` capsule
    static func makeBlurPanel() -> NSPanel {
        let width = margin + (capsuleSize.width + margin) * 3
        let height = margin + capsuleSize.height + 8 + labelHeight + margin
        let screenFrame = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let frame = NSRect(
            x: screenFrame.midX - width / 2, y: screenFrame.midY - height / 2,
            width: width, height: height)

        let panel = SpikePanel(frame: frame)
        panel.level = .statusBar
        panel.isMovableByWindowBackground = true

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))

        let masked = makeEffectView()
        masked.maskImage = capsuleMask(size: capsuleSize)

        let layerClipped = makeEffectView()
        layerClipped.wantsLayer = true
        layerClipped.layer?.cornerRadius = capsuleSize.height / 2
        layerClipped.layer?.cornerCurve = .continuous
        layerClipped.layer?.masksToBounds = true

        let material = NSHostingView(
            rootView: Capsule()
                .fill(.ultraThinMaterial)
                .frame(width: capsuleSize.width, height: capsuleSize.height))

        let columns: [(view: NSView, label: String)] = [
            (masked, "A  NSVisualEffectView + maskImage"),
            (layerClipped, "B  NSVisualEffectView + layer radius"),
            (material, "C  SwiftUI .ultraThinMaterial"),
        ]
        for (index, column) in columns.enumerated() {
            let x = margin + CGFloat(index) * (capsuleSize.width + margin)
            column.view.frame = NSRect(
                x: x, y: margin + labelHeight + 8,
                width: capsuleSize.width, height: capsuleSize.height)
            content.addSubview(column.view)

            let label = NSTextField(labelWithString: column.label)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.drawsBackground = true
            label.backgroundColor = NSColor.black.withAlphaComponent(0.65)
            label.frame = NSRect(x: x, y: margin, width: capsuleSize.width, height: labelHeight)
            content.addSubview(label)
        }

        panel.contentView = content
        return panel
    }

    private static func makeEffectView() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    private static func capsuleMask(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2
            ).fill()
            return true
        }
    }

    // MARK: - Experiment 4: notch-level test strip (V6)

    private static let stripWidth: CGFloat = 200
    private static let stripLevelOffset = 3

    /// A red strip, 200 × safe-area-top, at the top centre of the built-in
    /// screen at `mainMenu + 3`. Also logs the notch geometry.
    static func makeNotchStrip() -> NSPanel? {
        let screen = NSScreen.screens.first { screen in
            displayID(of: screen).map { CGDisplayIsBuiltin($0) != 0 } ?? false
        } ?? NSScreen.main
        guard let screen else {
            SpikeLog.write("notch: no screen found")
            return nil
        }

        let frame = screen.frame
        let safeTop = screen.safeAreaInsets.top
        let leftArea = screen.auxiliaryTopLeftArea
        let rightArea = screen.auxiliaryTopRightArea
        let notchWidth: CGFloat? = {
            guard let leftArea, let rightArea else { return nil }
            return frame.width - leftArea.width - rightArea.width
        }()

        let height = safeTop > 0 ? safeTop : 24
        let stripFrame = NSRect(
            x: frame.midX - stripWidth / 2, y: frame.maxY - height,
            width: stripWidth, height: height)

        let panel = SpikePanel(frame: stripFrame)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + stripLevelOffset)
        panel.isOpaque = true
        panel.backgroundColor = .systemRed
        panel.ignoresMouseEvents = true
        panel.setFrame(stripFrame, display: true)

        let screenName = screen.localizedName
        let visibleFrame = screen.visibleFrame
        let scale = screen.backingScaleFactor
        let level = panel.level.rawValue
        let mainMenuLevel = NSWindow.Level.mainMenu.rawValue
        let statusBarLevel = NSWindow.Level.statusBar.rawValue
        let menuBarThickness = NSStatusBar.system.thickness
        let panelFrame = panel.frame
        let builtin = displayID(of: screen).map { CGDisplayIsBuiltin($0) != 0 } ?? false
        SpikeLog.write(
            "notch: screen='\(screenName)' builtin=\(builtin) frame=\(frame) "
                + "visibleFrame=\(visibleFrame) scale=\(scale)")
        SpikeLog.write(
            "notch: safeAreaInsets.top=\(safeTop) auxiliaryTopLeftArea=\(describe(leftArea)) "
                + "auxiliaryTopRightArea=\(describe(rightArea)) statusBarThickness=\(menuBarThickness)")
        SpikeLog.write(
            "notch: computed notchWidth=\(notchWidth.map { "\($0)" } ?? "none (no notch)") "
                + "notchHeight=\(safeTop)")
        SpikeLog.write(
            "notch: strip requested=\(stripFrame) actual=\(panelFrame) level=\(level) "
                + "(mainMenu=\(mainMenuLevel), statusBar=\(statusBarLevel))")
        return panel
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    private static func describe(_ rect: NSRect?) -> String {
        rect.map { "\($0)" } ?? "nil"
    }
}
#endif
