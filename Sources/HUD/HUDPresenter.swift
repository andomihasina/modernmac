import AppKit
import SwiftUI

/// Puts what `HUDCoordinator` decides on screen: places the panel, fades it
/// in and out, and lets the pointer in only while it is on the HUD's shape.
@MainActor
final class HUDPresenter {
    enum DragEvent: Equatable {
        case began(HUDKind)
        case changed(Double)
        case ended
    }

    /// How often the pointer is checked against the shape while the HUD is up.
    private static let pointerCheckInterval: TimeInterval = 1.0 / 60.0

    let model: HUDViewModel
    private let panel = HUDPanel()
    private let options: () -> HUDOptions

    /// Where the HUD currently is; nil until it has been placed on a screen.
    private var placement: HUDPlacement?
    private var pointerTimer: Timer?
    /// Bumped on every show and hide; stale delayed work checks it and stops.
    private var generation = 0

    /// The pointer entered or left the shape.
    var onHoverChanged: ((Bool) -> Void)?
    var onDrag: ((DragEvent) -> Void)?

    #if DEBUG
    /// Options for a simulated HUD; dropped when it hides.
    var optionsOverride: HUDOptions?
    /// Treat the screen as having no notch; dropped when the HUD hides.
    var ignoresNotch = false
    #endif

    /// - Parameter options: Read every time the HUD is shown or updated.
    init(options: @escaping () -> HUDOptions) {
        self.options = options
        let initial = options()
        model = HUDViewModel(
            state: .volume(VolumeReading(level: 0, isMuted: false, deviceName: nil)),
            options: initial)

        let hosting = HUDHostingView(rootView: HUDRootView(model: model))
        // The panel's frame is ours to set; the content must not resize it.
        hosting.sizingOptions = []
        panel.contentView = hosting

        model.onDragChanged = { [weak self] level in self?.dragChanged(to: level) }
        model.onDragEnded = { [weak self] in self?.dragEnded() }
    }

    // MARK: - Presentation

    func apply(_ presentation: HUDPresentation) {
        guard presentation.isVisible, let state = presentation.state else {
            hide()
            return
        }

        let wasShown = model.phase == .shown
        let options = currentOptions
        if model.options != options { model.options = options }
        model.animatesLevel = wasShown && !model.isDragging
        if model.state != state { model.state = state }

        place(on: NSScreen.hudTarget(displayID: presentation.displayID), options: options)
        if !options.isInteractive { stopPointerTracking() }
        if !wasShown { show() }
    }

    private var currentOptions: HUDOptions {
        #if DEBUG
        if let optionsOverride { return optionsOverride }
        #endif
        return options()
    }

    private func place(on screen: NSScreen?, options: HUDOptions) {
        guard let screen else { return }
        var metrics = screen.metrics
        #if DEBUG
        if ignoresNotch {
            metrics.auxiliaryTopLeftWidth = nil
            metrics.auxiliaryTopRightWidth = nil
        }
        #endif
        let placement = options.style.placement(
            options: options,
            screen: metrics,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        self.placement = placement

        let notchSize = NotchLayout.notchRect(in: metrics)?.size
        if model.notchSize != notchSize { model.notchSize = notchSize }

        if panel.frame != placement.panelFrame {
            panel.setFrame(placement.panelFrame, display: false)
        }
        let level: NSWindow.Level = placement.isOverMenuBar ? HUDPanel.notchLevel : .statusBar
        if panel.level != level { panel.level = level }
    }

    private func show() {
        generation += 1
        let token = generation

        if !panel.isVisible {
            setPhaseWithoutAnimation(.idle)
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
        Log.trace { [placement, model] in
            "hud show \(model.state.kind) level=\(model.state.level) style=\(model.options.style.rawValue) "
                + "position=\(model.options.position.rawValue) "
                + "shape=\(placement?.hitFrame ?? .zero) panel=\(placement?.panelFrame ?? .zero) "
                + "notch=\(model.notchSize.map { "\($0)" } ?? "none")"
        }

        // One run loop turn later, so the content has drawn its starting
        // pose before it animates away from it.
        DispatchQueue.main.async { [self] in
            guard token == generation else { return }
            model.phase = .shown
            fadePanel(to: 1, duration: placement?.motion.appearFade ?? 0)
            if model.options.isInteractive { startPointerTracking() }
        }
    }

    private func hide() {
        stopPointerTracking()
        model.isDragging = false
        #if DEBUG
        optionsOverride = nil
        ignoresNotch = false
        #endif

        switch model.phase {
        case .leaving:
            return
        case .idle:
            // Ordered front and still waiting to appear: call that off.
            generation += 1
            panel.orderOut(nil)
            return
        case .shown:
            break
        }

        generation += 1
        let token = generation
        Log.trace { "hud hide" }
        model.phase = .leaving
        let motion = placement?.motion
            ?? HUDMotion(appearFade: 0, disappearFade: 0, orderOutDelay: 0)
        // Without a fade the panel stays opaque while the style retracts.
        if motion.disappearFade > 0 { fadePanel(to: 0, duration: motion.disappearFade) }
        DispatchQueue.main.asyncAfter(deadline: .now() + motion.orderOutDelay) { [self] in
            guard token == generation else { return }
            panel.orderOut(nil)
            panel.alphaValue = 0
            setPhaseWithoutAnimation(.idle)
        }
    }

    private func fadePanel(to alpha: CGFloat, duration: TimeInterval) {
        guard duration > 0 else {
            panel.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        }
    }

    private func setPhaseWithoutAnimation(_ phase: HUDViewModel.Phase) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.phase = phase }
    }

    // MARK: - Pointer

    // The panel is larger than the shape (shadow, animation room), so it
    // ignores the mouse except while the pointer is on the shape itself.
    // That is what lets a click one point outside reach the app below.
    // Polling the pointer position needs no event routing to an app that is
    // never active, and only runs while the HUD is up.

    private func startPointerTracking() {
        guard pointerTimer == nil else { return }
        let timer = Timer(timeInterval: Self.pointerCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        checkPointer()
    }

    private func stopPointerTracking() {
        pointerTimer?.invalidate()
        pointerTimer = nil
        panel.ignoresMouseEvents = true
        if model.isHovering {
            model.isHovering = false
            onHoverChanged?(false)
        }
    }

    private func checkPointer() {
        guard let placement else { return }
        // A style may grow while hovered (none does at present); the pointer
        // then stays "on the HUD" across the larger shape.
        let frame = model.isHovering ? placement.hoverHitFrame : placement.hitFrame
        let inside = model.isDragging || HUDLayout.shape(
            frame, cornerRadius: placement.hitCornerRadius, contains: NSEvent.mouseLocation)
        guard inside != model.isHovering else { return }
        model.isHovering = inside
        panel.ignoresMouseEvents = !inside
        onHoverChanged?(inside)
        Log.trace { "hud hover=\(inside)" }
    }

    // MARK: - Drag

    private func dragChanged(to level: Double) {
        guard model.phase == .shown else { return }
        if !model.isDragging {
            model.isDragging = true
            model.animatesLevel = false
            Log.trace { [model] in "hud drag began \(model.state.kind)" }
            onDrag?(.began(model.state.kind))
        }
        onDrag?(.changed(level))
    }

    private func dragEnded() {
        guard model.isDragging else { return }
        model.isDragging = false
        // Released outside the shape: end the hover first, so the short
        // drag-release delay applies instead of the full hide delay.
        checkPointer()
        onDrag?(.ended)
        Log.trace { [model] in "hud drag ended level=\(model.state.level)" }
    }
}
