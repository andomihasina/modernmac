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
    static let styles: [HUDStyle] = [.tahoe, .notch, .circular]
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
            count += try writeWindowSnapshots(to: outputDirectory)
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
        case .tahoe: return tahoeVariants(style: style, scheme: scheme)
        case .notch: return notchVariants(scheme: scheme)
        case .circular: return circularVariants(scheme: scheme)
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

    /// `circular`: the ring at its ends and in between, with and without
    /// the number, and two tiles on a near-black desktop for comparison with
    /// `docs/reference/circular-*.png` (87 and 40 there).
    private static func circularVariants(scheme: ColorScheme) -> [Variant] {
        let schemeName = schemeLabel(scheme)
        var options = HUDOptions()
        options.style = .circular
        var percent = options
        percent.showsPercentage = true

        func variant(_ parts: String..., state: HUDState, options: HUDOptions) -> Variant {
            Variant(
                name: (["circular"] + parts + [schemeName]).joined(separator: "-"),
                state: state, options: options, colorScheme: scheme)
        }

        var result: [Variant] = []
        for level in levels {
            result.append(variant("volume", levelName(level), state: volume(level), options: options))
        }
        result.append(variant("volume", "muted", state: volume(0.66, muted: true), options: options))
        for level in levels {
            result.append(
                variant("brightness", levelName(level), state: brightness(level), options: options))
        }

        // The smallest steps: one fine step from each end, and the first
        // level at which the filled arc has room to show.
        result.append(variant("volume", "fine", state: volume(1.0 / 64), options: options))
        result.append(variant("volume", "one-step", state: volume(1.0 / 16), options: options))
        result.append(variant("volume", "two-steps", state: volume(2.0 / 16), options: options))
        result.append(variant("volume", "almost-full", state: volume(63.0 / 64), options: options))

        result.append(variant("volume", "000", "percent", state: volume(0), options: percent))
        result.append(variant("volume", "066", "percent", state: volume(0.66), options: percent))
        result.append(variant("volume", "100", "percent", state: volume(1), options: percent))
        result.append(
            variant("volume", "muted", "percent", state: volume(0.66, muted: true), options: percent))
        result.append(
            variant("brightness", "033", "percent", state: brightness(0.33), options: percent))

        var hover = variant("volume", "066", "hover", state: volume(0.66), options: options)
        hover.isHovering = true
        result.append(hover)

        var contrast = variant("volume", "066", "contrast", state: volume(0.66), options: percent)
        contrast.increasesContrast = true
        result.append(contrast)

        var plainVolume = variant("volume", "087", "plain", state: volume(0.87), options: percent)
        plainVolume.plainBackdrop = true
        result.append(plainVolume)
        var plainBrightness = variant(
            "brightness", "040", "plain", state: brightness(0.40), options: percent)
        plainBrightness.plainBackdrop = true
        result.append(plainBrightness)

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

    // MARK: - Settings and onboarding

    /// The Settings panes and the onboarding window, light and dark. These
    /// are made of AppKit controls, which `ImageRenderer` cannot draw, so
    /// each is laid out in an offscreen window and captured from its view.
    /// Settings are read from a throwaway defaults suite: the pictures show
    /// the defaults, and nothing of the user's is touched.
    private static func writeWindowSnapshots(to directory: URL) throws -> Int {
        let suiteName = "com.ando.ModernMac.snapshots"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let permissions = PermissionManager()
        let progress = OnboardingProgress()
        let settings = AppSettings(defaults: defaults)
        let windows = AppWindows(
            settings: settings, permissions: permissions,
            launchAtLogin: LaunchAtLogin(), onboardingProgress: progress)

        var count = 0
        for (label, appearanceName) in [
            ("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua),
        ] {
            let appearance = NSAppearance(named: appearanceName)
            // The real window: toolbar tabs, resized to each pane in turn.
            let settingsWindow = windows.makeSettingsWindow()
            settingsWindow.appearance = appearance
            if let tabs = settingsWindow.contentViewController as? SettingsTabController {
                for (index, pane) in SettingsPane.allCases.enumerated() {
                    tabs.selectedTabViewItemIndex = index
                    tabs.fitWindowToSelectedTab(animated: false)
                    try capture(
                        settingsWindow, named: "settings-\(pane.rawValue)-\(label)", to: directory)
                    count += 1
                    guard pane == .appearance else { continue }
                    // The preview for the other styles; the window has to
                    // follow the hints that appear under the controls.
                    for style in [HUDStyle.notch, .circular] {
                        settings.style = style
                        settings.showPercentage = true
                        try capture(
                            settingsWindow,
                            named: "settings-appearance-\(style.rawValue)-\(label)", to: directory)
                        count += 1
                    }
                    settings.style = .tahoe
                    settings.showPercentage = false
                }
            }
            try capture(
                windows.onboardingView(), appearance: appearance,
                named: "onboarding-\(label)", to: directory)
            count += 1
        }
        return count
    }

    private static func capture(
        _ view: some View, appearance: NSAppearance?, named name: String, to directory: URL
    ) throws {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        try capture(window, named: name, to: directory)
    }

    /// The whole window, title bar and toolbar included, without showing it.
    private static func capture(_ window: NSWindow, named name: String, to directory: URL) throws {
        guard let frame = window.contentView?.superview else { throw RenderError.noImage(name) }
        frame.layoutSubtreeIfNeeded()
        // A turn of the run loop lets SwiftUI finish its first update.
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        frame.layoutSubtreeIfNeeded()

        guard let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else {
            throw RenderError.noImage(name)
        }
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError.noImage(name)
        }
        try data.write(to: directory.appendingPathComponent("\(name).png"))
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
