#if DEBUG
import SwiftUI

/// Phase 0 experiments, shown in the menu bar extra in Debug builds only.
struct SpikeMenu: View {
    var body: some View {
        let spike = SpikeController.shared
        Section("Spike (Phase 0)") {
            Text("Tap status: \(spike.tapStatus)")
            Button("Tap: log only") { spike.startTap(.listen) }
            Button("Tap: consume and handle") { spike.startTap(.consume) }
            Button("Tap: off") { spike.stopTap() }
            Divider()
            Button("Show blur test panel") { spike.toggleBlurPanel() }
            Button("Show notch-level test strip") { spike.toggleNotchStrip() }
            Button("Play feedback sound") { spike.playFeedbackSound() }
        }
    }
}
#endif
