import AppKit

/// Builds the engine and keeps it alive for the life of the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let permissions = PermissionManager()
    let launchAtLogin = LaunchAtLogin()
    let onboardingProgress = OnboardingProgress()
    private lazy var windows = AppWindows(
        settings: settings, permissions: permissions,
        launchAtLogin: launchAtLogin, onboardingProgress: onboardingProgress)

    private var audio: AudioController?
    private var coordinator: HUDCoordinator?
    private var presenter: HUDPresenter?
    private var keyHandler: KeyEventHandler?
    private var dragHandler: LevelDragHandler?
    private var tap: MediaKeyTap?
    #if DEBUG
    private var simulateHandler: SimulateURLHandler?
    #endif

    /// Unit tests are hosted in the app; they must not install a tap or ask
    /// for permissions.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isRunningTests else { return }
        #if DEBUG
        if let directory = SnapshotRenderer.requestedDirectory(in: CommandLine.arguments) {
            exit(SnapshotRenderer.run(outputDirectory: directory))
        }
        #endif
        startEngine()
    }

    /// The app was opened while it was already running. That is the way
    /// back to Settings when the menu bar icon is hidden (SPEC §6).
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        guard !isRunningTests else { return false }
        Log.app.notice("Reopened while running")
        showSettings()
        return false
    }

    func showSettings() {
        windows.showSettings()
    }

    func showOnboarding() {
        windows.showOnboarding()
    }

    private func startEngine() {
        let settings = settings
        let permissions = permissions
        let onboardingProgress = onboardingProgress

        let symbols = DisplayServicesBridge.symbolReport
            .map { "\($0.name)=\($0.isResolved)" }
            .joined(separator: " ")
        Log.display.notice("DisplayServices usable=\(DisplayServicesBridge.isUsable) \(symbols, privacy: .public)")

        // HUD: coordinator → presenter → panel.
        let scheduler = MainRunLoopScheduler()
        let coordinator = HUDCoordinator(
            scheduler: scheduler, hideDelay: { settings.clampedHideDelay })
        let presenter = HUDPresenter(options: { settings.hudOptions })
        coordinator.onChange = { presenter.apply($0) }
        presenter.onHoverChanged = { coordinator.setHovering($0) }

        // Hardware.
        let audio = AudioController()
        let brightness = BrightnessController()
        let feedback = FeedbackSound()
        let isFeedbackEnabled = {
            let stored = SystemFeedbackPreference.storedValue
            Log.trace { "feedback preference stored=\(stored.map { "\($0)" } ?? "absent")" }
            return settings.isFeedbackSoundEnabled(
                systemSetting: SystemFeedbackPreference.isEnabled)
        }

        // Drag on the HUD's bar → hardware. While a drag is on, the pointer
        // is the truth; what the hardware reports back is not shown.
        let dragHandler = LevelDragHandler(
            volume: audio,
            brightness: brightness,
            feedback: feedback,
            isFeedbackEnabled: isFeedbackEnabled,
            scheduler: scheduler,
            present: { coordinator.update($0) })
        dragHandler.trace = { Log.trace($0) }
        presenter.onDrag = { event in
            switch event {
            case .began(let kind):
                coordinator.beginDrag()
                dragHandler.begin(kind)
            case .changed(let level):
                dragHandler.change(to: level)
            case .ended:
                dragHandler.end()
                coordinator.endDrag()
            }
        }
        audio.onChange = { reading in
            guard !dragHandler.isActive else { return }
            coordinator.update(.volume(reading))
        }

        // Keys → hardware → HUD. The HUD update is deferred by one run loop
        // turn so the tap callback returns right after the hardware call.
        let keyHandler = KeyEventHandler(
            volume: audio,
            brightness: brightness,
            feedback: feedback,
            options: { settings.routingOptions },
            isFeedbackEnabled: isFeedbackEnabled,
            present: { state, displayID in
                DispatchQueue.main.async {
                    coordinator.show(state, displayID: displayID)
                    onboardingProgress.keyHandled()
                }
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
        self.presenter = presenter
        self.keyHandler = keyHandler
        self.dragHandler = dragHandler
        self.tap = tap

        #if DEBUG
        simulateHandler = SimulateURLHandler(
            onRequest: { request in
                presenter.optionsOverride = request.options(over: settings.hudOptions)
                presenter.ignoresNotch = request.forcesPill
                coordinator.show(request.state, hideAfter: request.hold)
            },
            onCommand: { [weak self] command in
                switch command {
                case .show(.settings): self?.showSettings()
                case .show(.onboarding): self?.showOnboarding()
                case .setMenuBarIcon(let isShown): settings.showMenuBarIcon = isShown
                }
            })
        #endif

        if permissions.isTrusted {
            if tap.start() { Log.app.notice("Takeover active") }
        } else {
            Log.app.notice("Not trusted for Accessibility; showing onboarding")
            showOnboarding()
        }
        permissions.startMonitoring()
    }
}
