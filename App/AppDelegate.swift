import AppKit

/// Builds the engine and keeps it alive for the life of the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let permissions = PermissionManager()

    private var audio: AudioController?
    private var coordinator: HUDCoordinator?
    private var placeholderHUD: PlaceholderHUD?
    private var keyHandler: KeyEventHandler?
    private var tap: MediaKeyTap?

    /// Unit tests are hosted in the app; they must not install a tap or ask
    /// for permissions.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        startEngine()
    }

    private func startEngine() {
        let settings = settings
        let permissions = permissions

        let symbols = DisplayServicesBridge.symbolReport
            .map { "\($0.name)=\($0.isResolved)" }
            .joined(separator: " ")
        Log.display.notice("DisplayServices usable=\(DisplayServicesBridge.isUsable) \(symbols, privacy: .public)")

        // HUD: coordinator → placeholder panel.
        let coordinator = HUDCoordinator(
            scheduler: MainRunLoopScheduler(), hideDelay: { settings.clampedHideDelay })
        let placeholderHUD = PlaceholderHUD()
        coordinator.onChange = { placeholderHUD.apply($0) }

        // Hardware.
        let audio = AudioController()
        audio.onChange = { coordinator.update(.volume($0)) }
        let brightness = BrightnessController()
        let feedback = FeedbackSound()

        // Keys → hardware → HUD. The HUD update is deferred by one run loop
        // turn so the tap callback returns right after the hardware call.
        let keyHandler = KeyEventHandler(
            volume: audio,
            brightness: brightness,
            feedback: feedback,
            options: { settings.routingOptions },
            isFeedbackEnabled: {
                let stored = SystemFeedbackPreference.storedValue
                Log.trace { "feedback preference stored=\(stored.map { "\($0)" } ?? "absent")" }
                return settings.isFeedbackSoundEnabled(systemSetting: stored ?? false)
            },
            present: { state, displayID in
                DispatchQueue.main.async { coordinator.show(state, displayID: displayID) }
            })
        keyHandler.trace = { Log.trace($0) }

        let tap = MediaKeyTap()
        tap.onEvent = { keyHandler.handle($0) }
        tap.onStopped = { _ in
            keyHandler.reset()
            permissions.refresh()
        }

        permissions.onTrustGranted = {
            if tap.start() { Log.app.notice("Takeover active") }
        }

        self.audio = audio
        self.coordinator = coordinator
        self.placeholderHUD = placeholderHUD
        self.keyHandler = keyHandler
        self.tap = tap

        if permissions.isTrusted {
            if tap.start() { Log.app.notice("Takeover active") }
        } else {
            // No onboarding window yet (Phase 5): ask straight away.
            Log.app.notice("Not trusted for Accessibility; requesting")
            permissions.requestTrust()
        }
        permissions.startMonitoring()
    }
}
