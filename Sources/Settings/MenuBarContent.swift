import SwiftUI

/// The menu bar extra's menu.
struct MenuBarContent: View {
    @Bindable var settings: AppSettings
    var permissions: PermissionManager

    var body: some View {
        Toggle("Enabled", isOn: $settings.isEnabled)

        if !permissions.isTrusted {
            Divider()
            Text("Accessibility permission needed")
            Button("Open Accessibility Settings…") {
                permissions.requestTrust()
                permissions.openSettings()
            }
        }

        Divider()
        Button("Quit ModernMac") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
