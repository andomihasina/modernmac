import AppKit
import ApplicationServices
import Observation

/// Accessibility trust: the one permission the event tap needs (FINDINGS V7).
@MainActor
@Observable
final class PermissionManager {
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    private static let pollInterval: TimeInterval = 1

    private(set) var isTrusted = AXIsProcessTrusted()

    /// Called once each time trust appears, so the tap can start without a relaunch.
    @ObservationIgnored var onTrustGranted: (() -> Void)?
    @ObservationIgnored private var pollTimer: Timer?

    /// Begins polling once per second while untrusted. Safe to call repeatedly.
    func startMonitoring() {
        refresh()
    }

    /// Re-reads trust now. Call when something suggests it changed, such as
    /// the tap noticing that trust was revoked.
    func refresh() {
        let trusted = AXIsProcessTrusted()
        let wasTrusted = isTrusted
        if trusted != wasTrusted { isTrusted = trusted }

        if trusted {
            pollTimer?.invalidate()
            pollTimer = nil
            if !wasTrusted {
                Log.permissions.notice("Accessibility trust granted")
                onTrustGranted?()
            }
        } else {
            if wasTrusted { Log.permissions.notice("Accessibility trust lost") }
            startPolling()
        }
    }

    /// Shows the system prompt that offers to open the Accessibility pane.
    func requestTrust() {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func openSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }
}
