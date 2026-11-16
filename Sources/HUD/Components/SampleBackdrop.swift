import SwiftUI

// Pretend desktops to draw a HUD on when there is no real one behind it:
// the snapshot renderer and the preview in Settings.

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
/// and, on a notched screen, the notch itself. In snapshots the mock notch
/// is dark grey, not black, so any part of it the HUD fails to cover shows.
struct MockScreenBackdrop: View {
    static let notchColor = Color(white: 0.22)
    static let notchCornerRadius: CGFloat = 8

    var colorScheme: ColorScheme
    var screen: ScreenMetrics
    /// The panel in screen coordinates; the view is exactly this big.
    var panelFrame: CGRect
    /// The Settings preview draws the notch black, as it looks on a Mac.
    var notchColor = MockScreenBackdrop.notchColor
    /// Fewer stand-in items, for a screen too narrow for the full set.
    var isCompact = false

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
                    if !isCompact {
                        Text("File")
                        Text("Edit")
                        Text("View")
                    }
                    Spacer()
                    Image(systemName: "wifi")
                    Image(systemName: "battery.75percent")
                    Text("9:41")
                }
                .font(.system(size: 13))
                .lineLimit(1)
                // Compact: spread to both ends, like a real menu bar. The
                // snapshot tiles keep the items together so that some show
                // in a tile much narrower than a screen.
                .fixedSize(horizontal: !isCompact, vertical: true)
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
                    .fill(notchColor)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(width: panelFrame.width, height: panelFrame.height, alignment: .topLeading)
    }
}
