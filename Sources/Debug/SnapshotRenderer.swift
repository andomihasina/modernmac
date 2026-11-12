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
    static let styles: [HUDStyle] = [.tahoe]
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
        let schemeName = schemeLabel(scheme)
        var options = HUDOptions()
        options.style = style

        func volume(_ level: Double, muted: Bool = false) -> HUDState {
            .volume(VolumeReading(
                level: level, isMuted: muted, deviceName: "MacBook Air Speakers"))
        }
        func brightness(_ level: Double) -> HUDState {
            .brightness(BrightnessReading(
                level: level, displayID: 0, displayName: "Built-in Display"))
        }
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
        model.phase = .shown
        model.isHovering = variant.isHovering

        let geometry = variant.options.style.geometry(options: variant.options)
        let size = HUDLayout.panelFrame(forShape: CGRect(origin: .zero, size: geometry.size)).size

        return HUDRootView(model: model)
            .frame(width: size.width, height: size.height)
            .background(SnapshotBackdrop(
                colorScheme: variant.colorScheme, isPlain: variant.plainBackdrop))
            .environment(\.colorScheme, variant.colorScheme)
            .environment(\.hudRenderMode, .snapshot)
            .environment(\.hudIncreaseContrast, variant.increasesContrast)
            .environment(\.hudReduceMotion, true)
    }

    /// Every variant of one appearance on a single image.
    static func sheet(_ variants: [Variant]) -> some View {
        let columns = [GridItem(.fixed(360), spacing: 0), GridItem(.fixed(360), spacing: 0)]
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
        .frame(width: 720)
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
#endif
