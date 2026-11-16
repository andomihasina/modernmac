import SwiftUI

/// The tabs of the Settings window (SPEC §6).
enum SettingsPane: String, CaseIterable, Sendable {
    case general
    case appearance
    case behaviour
    case about

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .behaviour: return "Behaviour"
        case .about: return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .behaviour: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Names shown in the UI

extension HUDStyle {
    /// SPEC §1, "Name in UI".
    var displayName: String {
        switch self {
        case .tahoe: return "macOS 26"
        case .notch: return "Notch"
        case .circular: return "Circular"
        }
    }

    /// `notch` sits at the notch; the others follow the position setting.
    var usesPosition: Bool { self != .notch }
    /// Only `tahoe` has room for the device name.
    var showsDeviceName: Bool { self == .tahoe }
}

extension HUDPosition {
    var displayName: String {
        switch self {
        case .topRight: return "Top right"
        case .topLeft: return "Top left"
        case .topCenter: return "Top centre"
        case .bottomCenter: return "Bottom centre"
        }
    }
}

extension AppSettings.FeedbackSoundPolicy {
    var displayName: String {
        switch self {
        case .followSystem: return "Follow system setting"
        case .always: return "Always"
        case .never: return "Never"
        }
    }
}

// MARK: - Panes

/// One tab's content. Every pane has the same width and is as tall as its
/// content, so the window can resize to it.
struct SettingsPaneView: View {
    static let width: CGFloat = 480

    let pane: SettingsPane
    @Bindable var settings: AppSettings
    var permissions: PermissionManager
    var launchAtLogin: LaunchAtLogin
    var showOnboarding: () -> Void

    var body: some View {
        Group {
            switch pane {
            case .general:
                GeneralPane(
                    settings: settings, permissions: permissions,
                    launchAtLogin: launchAtLogin, showOnboarding: showOnboarding)
            case .appearance:
                AppearancePane(settings: settings)
            case .behaviour:
                BehaviourPane(settings: settings)
            case .about:
                AboutPane()
            }
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralPane: View {
    @Bindable var settings: AppSettings
    var permissions: PermissionManager
    var launchAtLogin: LaunchAtLogin
    var showOnboarding: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.isEnabled) {
                    Text("Enable ModernMac")
                    Text("When off, macOS shows its own volume and brightness overlay.")
                }
                Toggle(isOn: Binding(
                    get: { launchAtLogin.isOn },
                    set: { launchAtLogin.setOn($0) })
                ) {
                    Text("Launch at login")
                    if launchAtLogin.state == .needsApproval {
                        Text("Waiting for approval in System Settings → General → Login Items.")
                    } else if let error = launchAtLogin.errorMessage {
                        Text(error)
                    }
                }
                if launchAtLogin.state == .needsApproval {
                    Button("Open Login Items Settings…") {
                        launchAtLogin.openLoginItemsSettings()
                    }
                }
                Toggle(isOn: $settings.showMenuBarIcon) {
                    Text("Show icon in menu bar")
                    Text("With the icon hidden, open ModernMac again to come back to this window.")
                }
            }

            Section("Permission") {
                LabeledContent {
                    if !permissions.isTrusted {
                        Button("Set Up…", action: showOnboarding)
                    }
                } label: {
                    Label {
                        Text(
                            permissions.isTrusted
                                ? "Accessibility access granted"
                                : "Accessibility access needed")
                        if !permissions.isTrusted {
                            Text("Until then the keys work as usual, with the macOS overlay.")
                        }
                    } icon: {
                        Image(
                            systemName: permissions.isTrusted
                                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(permissions.isTrusted ? Color.green : Color.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .onAppear { launchAtLogin.refresh() }
    }
}

private struct AppearancePane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            HUDPreview(options: settings.hudOptions)
                .padding(.top, 20)

            Form {
                Section {
                    Picker("Style", selection: $settings.style) {
                        ForEach(HUDStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(selection: $settings.position) {
                        ForEach(HUDPosition.allCases, id: \.self) { position in
                            Text(position.displayName).tag(position)
                        }
                    } label: {
                        Text("Position")
                        if !settings.style.usesPosition {
                            Text("The Notch style always sits at the notch.")
                        }
                    }
                    .disabled(!settings.style.usesPosition)
                }

                Section {
                    Toggle("Show percentage", isOn: $settings.showPercentage)
                    Toggle(isOn: $settings.showDeviceName) {
                        Text("Show device name")
                        if !settings.style.showsDeviceName {
                            Text("Only the macOS 26 style has room for it.")
                        }
                    }
                    .disabled(!settings.style.showsDeviceName)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }
}

private struct BehaviourPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                LabeledContent("Hide after") {
                    HStack(spacing: 10) {
                        Slider(
                            value: $settings.hideDelay,
                            in: AppSettings.hideDelayRange, step: 0.1
                        ) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("0.8")
                        } maximumValueLabel: {
                            Text("3.0")
                        }
                        .labelsHidden()
                        .frame(width: 210)
                        .accessibilityLabel("Hide after")
                        .accessibilityValue(hideDelayText)
                        Text(hideDelayText)
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle(isOn: $settings.isInteractive) {
                    Text("Interactive")
                    Text("The HUD stays open under the pointer, and dragging on it sets the level.")
                }
            }

            Section {
                Picker(selection: $settings.playFeedbackSound) {
                    ForEach(AppSettings.FeedbackSoundPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                } label: {
                    Text("Feedback sound")
                    Text("The click on each volume step. Holding ⇧ inverts it for one press.")
                }
            }

            Section("Keys") {
                Toggle(isOn: $settings.handleVolume) {
                    Text("Volume and mute keys")
                }
                Toggle(isOn: $settings.handleBrightness) {
                    Text("Brightness keys")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private var hideDelayText: String {
        String(format: "%.1f s", settings.clampedHideDelay)
    }
}

private struct AboutPane: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            AppBadge(size: 72)
            Text("ModernMac")
                .font(.title2.weight(.semibold))
            Text(version)
                .foregroundStyle(.secondary)
            Text(
                "A modern volume and brightness HUD for macOS, in place of the large overlay in the middle of the screen.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
                .padding(.top, 4)
            Text(
                "ModernMac only sees the volume, mute and brightness keys. Quit it and macOS takes them back at once.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}

/// Stands in for an app icon until there is one.
struct AppBadge: View {
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.36, green: 0.42, blue: 0.95),
                             Color(red: 0.62, green: 0.30, blue: 0.85)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}
