import SwiftUI

/// The menu bar extra's menu (SPEC §6).
struct MenuBarContent: View {
    @Bindable var settings: AppSettings
    var permissions: PermissionManager
    var showSettings: () -> Void
    var showOnboarding: () -> Void

    var body: some View {
        Toggle("Enabled", isOn: $settings.isEnabled)

        Picker("Style", selection: $settings.style) {
            ForEach(HUDStyle.allCases, id: \.self) { style in
                Text(style.displayName).tag(style)
            }
        }

        if !permissions.isTrusted {
            Divider()
            Text("Accessibility access needed")
            Button("Set Up Access…", action: showOnboarding)
        }

        Divider()
        Button("Settings…", action: showSettings)
            .keyboardShortcut(",")
        Button("Quit ModernMac") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
