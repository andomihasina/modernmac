import SwiftUI

@main
struct ModernMacApp: App {
    var body: some Scene {
        MenuBarExtra("ModernMac", systemImage: "speaker.wave.2") {
            Text("ModernMac")
            #if DEBUG
            Divider()
            SpikeMenu()
            #endif
            Divider()
            Button("Quit ModernMac") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
