import Observation
import SwiftUI

/// What the onboarding window follows besides the permission itself.
@MainActor
@Observable
final class OnboardingProgress {
    /// ModernMac handled a key since the window opened: the takeover works.
    private(set) var didHandleKey = false

    func keyHandled() {
        if !didHandleKey { didHandleKey = true }
    }

    func reset() {
        if didHandleKey { didHandleKey = false }
    }
}

/// Shown at launch while Accessibility access is missing (SPEC §6): what the
/// app does, why it needs the permission, a button that asks for it, a
/// status that turns to granted on its own, and then "try your keys".
struct OnboardingView: View {
    static let width: CGFloat = 460

    var permissions: PermissionManager
    var progress: OnboardingProgress
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            permissionStep
            tryStep
            HStack {
                Spacer()
                Button(isFinished ? "Done" : "Close", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var isFinished: Bool { permissions.isTrusted && progress.didHandleKey }

    private var header: some View {
        HStack(spacing: 16) {
            AppBadge(size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to ModernMac")
                    .font(.title2.weight(.semibold))
                Text("A modern HUD for the volume and brightness keys, in place of the large overlay macOS shows.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissionStep: some View {
        Step(number: 1, title: "Allow Accessibility access", isDone: permissions.isTrusted) {
            Text("ModernMac catches the volume, mute and brightness keys so it can change the level and show its own HUD. macOS calls that Accessibility access. ModernMac sees those keys only, nothing else you type.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if permissions.isTrusted {
                StatusLine(symbol: "checkmark.circle.fill", tint: .green, text: "Access granted")
            } else {
                Text("In the list that opens, switch ModernMac on. This window notices by itself.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button("Open Accessibility Settings…") {
                        // The request puts ModernMac into the list; then the
                        // pane is opened where that list is.
                        permissions.requestTrust()
                        permissions.openSettings()
                    }
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for access…").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var tryStep: some View {
        Step(number: 2, title: "Try your volume keys", isDone: isFinished) {
            if isFinished {
                StatusLine(
                    symbol: "checkmark.circle.fill", tint: .green,
                    text: "It works. That was ModernMac's HUD.")
            } else {
                Text("Press volume up or down. The new HUD appears instead of the macOS one.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .opacity(permissions.isTrusted ? 1 : 0.45)
    }
}

private struct Step<Content: View>: View {
    var number: Int
    var title: String
    var isDone: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(isDone ? Color.green : Color.accentColor)
                if isDone {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                } else {
                    Text("\(number)").font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct StatusLine: View {
    var symbol: String
    var tint: Color
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}
