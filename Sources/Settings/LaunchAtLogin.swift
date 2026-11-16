import Observation
import ServiceManagement

/// "Launch at login" through `SMAppService.mainApp`. The system owns the
/// state (the user can also change it in System Settings → Login Items), so
/// nothing is stored here: it is read back from the service (SPEC §6).
@MainActor
@Observable
final class LaunchAtLogin {
    enum State: Equatable, Sendable {
        case off
        case on
        /// Registered, but the user has to allow it in System Settings.
        case needsApproval
    }

    private(set) var state = LaunchAtLogin.currentState()
    /// Why the last change failed; nil when it went through.
    private(set) var errorMessage: String?

    /// What the toggle shows: registered, whether or not approval is pending.
    var isOn: Bool { state != .off }

    /// Re-reads the state. Call when Settings comes to the front: it can
    /// change in System Settings behind the app's back.
    func refresh() {
        let current = Self.currentState()
        if current != state { state = current }
    }

    func setOn(_ on: Bool) {
        errorMessage = nil
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.app.notice("Launch at login set to \(on)")
        } catch {
            errorMessage = error.localizedDescription
            Log.app.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func currentState() -> State {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        // `.notFound` is also what an app that was never registered reports.
        case .notRegistered, .notFound: return .off
        @unknown default: return .off
        }
    }
}
