import SwiftUI

/// The HUD's SF Symbol. It sits in a fixed-width box so the bar next to it
/// does not move when the symbol changes, and cross-fades when it does.
struct HUDIcon: View {
    static let swapAnimation = Animation.easeInOut(duration: 0.15)

    var symbolName: String
    /// SF Symbols variable value (speaker waves).
    var value: Double
    var pointSize: CGFloat
    var weight: Font.Weight
    var boxWidth: CGFloat
    var alignment: Alignment = .leading

    var body: some View {
        ZStack(alignment: alignment) {
            // Only the speaker's waves follow the level. Any other symbol is
            // drawn solid: a variable value of 0 would dim the slashed speaker.
            Image(systemName: symbolName, variableValue: symbolName.contains("wave") ? value : nil)
                .font(.system(size: pointSize, weight: weight))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .id(symbolName)
                .transition(.opacity)
        }
        .frame(width: boxWidth, alignment: alignment)
        .animation(Self.swapAnimation, value: symbolName)
    }
}
