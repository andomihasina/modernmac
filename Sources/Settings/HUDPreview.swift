import SwiftUI

/// The live preview in Settings → Appearance: the real style view on a small
/// pretend screen, stepping through a few levels (SPEC §6). The pretend
/// screen is exactly as big as the preview, so the position setting shows
/// too. Glass is drawn in `.snapshot` mode: there is no desktop behind it.
struct HUDPreview: View {
    // MARK: Tunable numbers (points)

    static let size = CGSize(width: 440, height: 170)
    static let cornerRadius: CGFloat = 10
    /// Menu bar of the pretend screen when it has no notch.
    static let menuBarHeight: CGFloat = 24
    /// The pretend notch, for the `notch` style: the size of the one on
    /// Ando's MacBook Air. Only the preview uses this; the real HUD always
    /// measures the screen it is on.
    static let notchSize = CGSize(width: 179, height: 32)
    static let stepInterval: Duration = .milliseconds(1300)

    /// What the preview steps through.
    static let samples: [HUDState] = [
        .volume(VolumeReading(level: 0.35, isMuted: false, deviceName: "MacBook Air Speakers")),
        .volume(VolumeReading(level: 0.6, isMuted: false, deviceName: "MacBook Air Speakers")),
        .volume(VolumeReading(level: 0.85, isMuted: false, deviceName: "MacBook Air Speakers")),
        .brightness(BrightnessReading(level: 0.75, displayID: 0, displayName: "Built-in Display")),
        .brightness(BrightnessReading(level: 0.45, displayID: 0, displayName: "Built-in Display")),
    ]

    /// The pretend screen a style is shown on: notched for `notch`, with a
    /// plain menu bar otherwise.
    static func screen(for style: HUDStyle) -> ScreenMetrics {
        let frame = CGRect(origin: .zero, size: size)
        switch style {
        case .notch:
            let left = ((size.width - notchSize.width) / 2).rounded(.down)
            return ScreenMetrics(
                frame: frame,
                visibleFrame: CGRect(
                    x: 0, y: 0, width: size.width, height: size.height - notchSize.height),
                safeAreaTop: notchSize.height,
                auxiliaryTopLeftWidth: left,
                auxiliaryTopRightWidth: size.width - notchSize.width - left)
        case .tahoe, .circular:
            return ScreenMetrics(
                frame: frame,
                visibleFrame: CGRect(
                    x: 0, y: 0, width: size.width, height: size.height - menuBarHeight))
        }
    }

    // MARK: View

    /// The user's options; the preview follows them as they change.
    var options: HUDOptions

    @State private var model = HUDViewModel(state: HUDPreview.samples[0])
    @State private var sampleIndex = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let screen = Self.screen(for: options.style)
        let placement = options.style.placement(
            options: options, screen: screen, reduceMotion: false)
        let panel = MockScreenBackdrop.local(placement.panelFrame, in: screen.frame)

        ZStack(alignment: .topLeading) {
            MockScreenBackdrop(
                colorScheme: colorScheme, screen: screen, panelFrame: screen.frame,
                notchColor: .black, isCompact: true)
            HUDRootView(model: model)
                .frame(width: panel.width, height: panel.height)
                .offset(x: panel.minX, y: panel.minY)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .environment(\.hudRenderMode, .snapshot)
        // A picture of the HUD, not the HUD: it takes no pointer.
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Preview of the HUD")
        .onChange(of: options, initial: true) { _, options in
            apply(options)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.stepInterval)
                guard !Task.isCancelled else { return }
                sampleIndex = (sampleIndex + 1) % Self.samples.count
                model.animatesLevel = true
                model.state = Self.samples[sampleIndex]
            }
        }
    }

    private func apply(_ options: HUDOptions) {
        var options = options
        options.isInteractive = false
        model.options = options
        model.notchSize = NotchLayout.notchRect(in: Self.screen(for: options.style))?.size
        if model.phase != .shown {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { model.phase = .shown }
        }
    }
}
