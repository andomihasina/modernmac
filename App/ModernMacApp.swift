import SwiftUI

@main
struct ModernMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The one scene. Settings and onboarding are AppKit windows owned by
        // the delegate, so they can open without the menu bar icon.
        MenuBarExtra(
            "ModernMac", systemImage: "speaker.wave.2",
            isInserted: Bindable(appDelegate.settings).showMenuBarIcon
        ) {
            MenuBarContent(
                settings: appDelegate.settings,
                permissions: appDelegate.permissions,
                showSettings: { appDelegate.showSettings() },
                showOnboarding: { appDelegate.showOnboarding() })
        }
    }
}
