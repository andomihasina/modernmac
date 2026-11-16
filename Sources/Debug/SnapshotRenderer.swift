#if DEBUG
import AppKit
import SwiftUI

/// `ModernMac --snapshots <dir>`: renders the HUD styles offscreen to @2x
/// PNGs, so the look can be reviewed without the real panel (SPEC §7).
///
/// Per style: every kind × level {0, 0.33, 0.66, 1} + muted × {light, dark},
/// a few option variants, and one contact sheet per appearance.
@MainActor
enum SnapshotRenderer {
    /// Styles that have a view of their own so far.
    static let styles: [HUDStyle] = [.tahoe, .notch]
    static let levels: [Double] = [0, 0.33, 0.66, 1]
    static let scale: CGFloat = 2

    struct Variant {
        var name: String
        var state: HUDState
        var options: HUDOptions
        var colorScheme: ColorScheme
        var isHovering = false
        var increasesContrast = false
        /// A near-black desktop like the one in `docs/reference/`.
        var plainBackdrop = false
        /// The pretend screen the HUD is placed on.
        var screen = MockScreen.external
        /// Draw the screen's menu bar (and notch) behind the HUD.
        var showsScreenChrome = false
        var phase = HUDViewModel.Phase.shown
        /// Outline the mock notch on top, to judge alignment.
        var showsGuides = false
    }

    /// Screens to place snapshots on. The notched one has the values logged
    /// on Ando's MacBook Air (FINDINGS V6).
    enum MockScreen {
        static let notched = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            visibleFrame: CGRect(x: 0, y: 58, width: 1470, height: 861),
            safeAreaTop: 32,
            auxiliaryTopLeftWidth: 646,
            auxiliaryTopRightWidth: 645)
        static let external = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055))
    }

    /// The directory after `--snapshots`, if the flag is there.
    static func requestedDirectory(in arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: "--snapshots"),
              arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    /// Returns the process exit code.
    static func run(outputDirectory: URL) -> Int32 {
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory, withIntermediateDirectories: true)
            var count = 0
            for style in styles {
                for scheme in [ColorScheme.light, .dark] {
                    let variants = variants(style: style, scheme: scheme)
                    for variant in variants {
                        try write(tile(variant), named: variant.name, to: outputDirectory)
                        count += 1
                    }
                    let sheetName = "sheet-\(style.rawValue)-\(schemeLabel(scheme))"
                    try write(sheet(variants), named: sheetName, to: outputDirectory)
                    count += 1
                }
            }
            print("Wrote \(count) snapshots to \(outputDirectory.path)")
            return 0
        } catch {
            FileHandle.standardError.write(Data("Snapshot rendering failed: \(error)\n".utf8))
            return 1
        }
    }

    // MARK: - Variants

    static func variants(style: HUDStyle, scheme: ColorScheme) -> [Variant] {
        switch style {
        case .tahoe, .circular: return tahoeVariants(style: style, scheme: scheme)
        case .notch: return notchVariants(scheme: scheme)
        }
    }

    private static func volume(_ level: Double, muted: Bool = false) -> HUDState {
        .volume(VolumeReading(level: level, isMuted: muted, deviceName: "MacBook Air Speakers"))
    }

    private static func brightness(_ level: Double) -> HUDState {
        .brightness(BrightnessReading(level: level, displayID: 0, displayName: "Built-in Display"))
    }

    private static func tahoeVariants(style: HUDStyle, scheme: ColorScheme) -> [Variant] {
        let schemeName = schemeLabel(scheme)
        var options = HUDOptions()
        options.style = style

        func name(_ parts: String...) -> String {
            ([style.rawValue] + parts + [schemeName]).joined(separator: "-")
        }
        func variant(_ name: String, _ state: HUDState, _ options: HUDOptions) -> Variant {
            Variant(name: name, state: state, options: options, colorScheme: scheme)
        }

        var result: [Variant] = []
        for level in levels {
            result.append(variant(name("volume", levelName(level)), volume(level), options))
        }
        result.append(variant(name("volume", "muted"), volume(0.66, muted: true), options))
        for level in levels {
            result.append(variant(name("brightness", levelName(level)), brightness(level), options))
        }

        // One fine step: the smallest fill the bar ever shows.
        result.append(variant(name("volume", "fine"), volume(1.0 / 64), options))

        var percent = options
        percent.showsPercentage = true
        result.append(variant(name("volume", "066", "percent"), volume(0.66), percent))
        result.append(variant(name("volume", "100", "percent"), volume(1), percent))

        var named = options
        named.showsDeviceName = true
        result.append(variant(name("volume", "066", "name"), volume(0.66), named))
        named.showsPercentage = true
        result.append(variant(name("brightness", "033", "name", "percent"), brightness(0.33), named))

        var hover = variant(name("volume", "066", "hover"), volume(0.66), options)
        hover.isHovering = true
        result.append(hover)

        var contrast = variant(name("volume", "066", "contrast"), volume(0.66), options)
        contrast.increasesContrast = true
        result.append(contrast)

        // For comparison with docs/reference/classic-*.png.
        var plainVolume = variant(name("volume", "082", "plain"), volume(0.82), options)
        plainVolume.plainBackdrop = true
        result.append(plainVolume)
        var plainBrightness = variant(name("brightness", "047", "plain"), brightness(0.47), options)
        plainBrightness.plainBackdrop = true
        result.append(plainBrightness)

        return result
    }

    /// `notch` on a notched screen, then its pill on a screen without one.
    /// The backdrop draws the menu bar and a mock notch so alignment shows.
    private static func notchVariants(scheme: ColorScheme) -> [Variant] {
        let schemeName = schemeLabel(scheme)
        var options = HUDOptions()
        options.style = .notch
        var percent = options
        percent.showsPercentage = true

        func variant(
            _ prefix: String, _ parts: [String], _ state: HUDState, _ options: HUDOptions,
            on screen: ScreenMetrics
        ) -> Variant {
            var variant = Variant(
                name: ([prefix] + parts + [schemeName]).joined(separator: "-"),
                state: state, options: options, colorScheme: scheme)
            variant.screen = screen
            variant.showsScreenChrome = true
            return variant
        }
        func notch(_ parts: String..., state: HUDState, options: HUDOptions) -> Variant {
            variant("notch", parts, state, options, on: MockScreen.notched)
        }
        func pill(_ parts: String..., state: HUDState, options: HUDOptions) -> Variant {
            variant("pill", parts, state, options, on: MockScreen.external)
        }

        var result: [Variant] = []
        for level in levels {
            result.append(notch("volume", levelName(level), state: volume(level), options: options))
        }
        result.append(notch("volume", "muted", state: volume(0.66, muted: true), options: options))
        for level in levels {
            result.append(
                notch("brightness", levelName(level), state: brightness(level), options: options))
        }
        result.append(notch("volume", "066", "percent", state: volume(0.66), options: percent))
        result.append(notch("volume", "100", "percent", state: volume(1), options: percent))

        var hover = notch("volume", "066", "hover", state: volume(0.66), options: options)
        hover.isHovering = true
        result.append(hover)

        // Collapsed must be exactly the notch: nothing of the HUD may show.
        var collapsed = notch("volume", "066", "collapsed", state: volume(0.66), options: options)
        collapsed.phase = .idle
        result.append(collapsed)

        var guides = notch("volume", "066", "guides", state: volume(0.66), options: options)
        guides.showsGuides = true
        result.append(guides)

        for level in levels {
            result.append(pill("volume", levelName(level), state: volume(level), options: options))
        }
        result.append(pill("volume", "muted", state: volume(0.66, muted: true), options: options))
        for level in levels {
            result.append(
                pill("brightness", levelName(level), state: brightness(level), options: options))
        }
        result.append(pill("volume", "100", "percent", state: volume(1), options: percent))
        var pillHover = pill("volume", "066", "hover", state: volume(0.66), options: options)
        pillHover.isHovering = true
        result.append(pillHover)
        var pillContrast = pill("volume", "066", "contrast", state: volume(0.66), options: options)
        pillContrast.increasesContrast = true
        result.append(pillContrast)

        return result
    }

    private static func levelName(_ level: Double) -> String {
        String(format: "%03d", Int((level * 100).rounded()))
    }

    private static func schemeLabel(_ scheme: ColorScheme) -> String {
        scheme == .dark ? "dark" : "light"
    }

    // MARK: - Views

    /// One HUD on a piece of desktop, sized like the real panel.
    static func tile(_ variant: Variant) -> some View {
        let model = HUDViewModel(state: variant.state, options: variant.options)
        model.phase = variant.phase
        model.isHovering = variant.isHovering
        model.notchSize = NotchLayout.notchRect(in: variant.screen)?.size

        // Reduce Motion is off so that a collapsed pose renders collapsed.
        let placement = variant.options.style.placement(
            options: variant.options, screen: variant.screen, reduceMotion: false)
        let size = placement.panelFrame.size

        return HUDRootView(model: model)
            .frame(width: size.width, height: size.height)
            .background {
                if variant.showsScreenChrome {
                    MockScreenBackdrop(
                        colorScheme: variant.colorScheme, screen: variant.screen,
                        panelFrame: placement.panelFrame)
                } else {
                    SnapshotBackdrop(
                        colorScheme: variant.colorScheme, isPlain: variant.plainBackdrop)
                }
            }
            .overlay {
                if variant.showsGuides {
                    MockScreenGuides(screen: variant.screen, panelFrame: placement.panelFrame)
                }
            }
            .clipped()
            .environment(\.colorScheme, variant.colorScheme)
            .environment(\.hudRenderMode, .snapshot)
            .environment(\.hudIncreaseContrast, variant.increasesContrast)
            .environment(\.hudReduceMotion, false)
    }

    /// Every variant of one appearance on a single image.
    static func sheet(_ variants: [Variant]) -> some View {
        let columns = [GridItem(.fixed(400), spacing: 0), GridItem(.fixed(400), spacing: 0)]
        return LazyVGrid(columns: columns, alignment: .center, spacing: 0) {
            ForEach(variants, id: \.name) { variant in
                VStack(spacing: 0) {
                    tile(variant)
                    Text(variant.name)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(white: 0.75))
                        .padding(.vertical, 3)
                }
            }
        }
        .frame(width: 800)
        .background(Color(white: 0.08))
    }

    // MARK: - Output

    private enum RenderError: Error {
        case noImage(String)
    }

    private static func write(_ view: some View, named name: String, to directory: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image)
                .representation(using: .png, properties: [:])
        else { throw RenderError.noImage(name) }
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

/// A stand-in desktop: a wallpaper-like gradient, or a near-black one.
struct SnapshotBackdrop: View {
    var colorScheme: ColorScheme
    var isPlain = false

    var body: some View {
        if isPlain {
            Color(red: 0.05, green: 0.06, blue: 0.08)
        } else {
            ZStack {
                LinearGradient(colors: base, startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(
                    colors: [accent.opacity(0.9), accent.opacity(0)],
                    center: UnitPoint(x: 0.78, y: 0.2), startRadius: 0, endRadius: 170)
                RadialGradient(
                    colors: [glow.opacity(0.8), glow.opacity(0)],
                    center: UnitPoint(x: 0.15, y: 0.95), startRadius: 0, endRadius: 150)
            }
        }
    }

    private var base: [Color] {
        colorScheme == .dark
            ? [Color(red: 0.10, green: 0.12, blue: 0.32), Color(red: 0.32, green: 0.12, blue: 0.40),
               Color(red: 0.05, green: 0.25, blue: 0.33)]
            : [Color(red: 0.45, green: 0.70, blue: 0.96), Color(red: 0.80, green: 0.74, blue: 0.95),
               Color(red: 0.99, green: 0.80, blue: 0.66)]
    }

    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 0.95, green: 0.40, blue: 0.55) : Color(red: 1.0, green: 0.93, blue: 0.70)
    }

    private var glow: Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.60, blue: 0.85) : Color(red: 0.35, green: 0.55, blue: 0.95)
    }
}
/// The top of a pretend screen behind a HUD panel: wallpaper, menu bar
/// and, on a notched screen, the notch itself. The mock notch is drawn in
/// dark grey, not black, so any part of it the HUD fails to cover shows.
struct MockScreenBackdrop: View {
    static let notchColor = Color(white: 0.22)
    static let notchCornerRadius: CGFloat = 8

    var colorScheme: ColorScheme
    var screen: ScreenMetrics
    /// The panel in screen coordinates; the view is exactly this big.
    var panelFrame: CGRect

    /// Menu bar height: the notch strip on a notched screen.
    static func menuBarHeight(of screen: ScreenMetrics) -> CGFloat {
        screen.safeAreaTop > 0 ? screen.safeAreaTop : screen.frame.maxY - screen.visibleFrame.maxY
    }

    /// A rectangle in screen coordinates → the view's top-left coordinates.
    static func local(_ rect: CGRect, in panelFrame: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - panelFrame.minX, y: panelFrame.maxY - rect.maxY,
            width: rect.width, height: rect.height)
    }

    var body: some View {
        let barHeight = Self.menuBarHeight(of: screen)
        let screenTop = panelFrame.maxY - screen.frame.maxY  // > 0: panel reaches above the screen
        let isDark = colorScheme == .dark

        ZStack(alignment: .topLeading) {
            SnapshotBackdrop(colorScheme: colorScheme)

            // Above the top edge of the screen there is only bezel.
            Color.black.frame(height: max(0, screenTop))

            // Menu bar with a few stand-in items.
            ZStack {
                (isDark ? Color.black.opacity(0.45) : Color.white.opacity(0.55))
                HStack(spacing: 14) {
                    Image(systemName: "apple.logo")
                    Text("Finder").fontWeight(.semibold)
                    Text("File")
                    Text("Edit")
                    Text("View")
                    Spacer()
                    Image(systemName: "wifi")
                    Image(systemName: "battery.75percent")
                    Text("9:41")
                }
                .font(.system(size: 13))
                .lineLimit(1)
                .fixedSize()
                .frame(width: panelFrame.width - 24)
                .clipped()
                .foregroundStyle(isDark ? Color.white : Color.black)
                .padding(.horizontal, 12)
            }
            .frame(height: barHeight)
            .offset(y: max(0, screenTop))

            if let notch = NotchLayout.notchRect(in: screen) {
                let rect = Self.local(notch, in: panelFrame)
                UnevenRoundedRectangle(
                    bottomLeadingRadius: Self.notchCornerRadius,
                    bottomTrailingRadius: Self.notchCornerRadius)
                    .fill(Self.notchColor)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(width: panelFrame.width, height: panelFrame.height, alignment: .topLeading)
    }
}

/// Outline of the mock notch, drawn over the HUD.
struct MockScreenGuides: View {
    var screen: ScreenMetrics
    var panelFrame: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let notch = NotchLayout.notchRect(in: screen) {
                let rect = MockScreenBackdrop.local(notch, in: panelFrame)
                UnevenRoundedRectangle(
                    bottomLeadingRadius: MockScreenBackdrop.notchCornerRadius,
                    bottomTrailingRadius: MockScreenBackdrop.notchCornerRadius)
                    .strokeBorder(Color(red: 1, green: 0.2, blue: 0.8), lineWidth: 0.5)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(width: panelFrame.width, height: panelFrame.height, alignment: .topLeading)
    }
}
#endif
