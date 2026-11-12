import SwiftUI

@main
struct ModernMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("ModernMac", systemImage: "speaker.wave.2") {
            MenuBarContent(settings: appDelegate.settings, permissions: appDelegate.permissions)
        }
    }
}
