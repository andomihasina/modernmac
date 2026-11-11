#if DEBUG
import AppKit
import ApplicationServices
import Observation

/// Drives the Phase 0 experiments from the menu bar. Throwaway.
@MainActor
@Observable
final class SpikeController {
    static let shared = SpikeController()

    private(set) var tapStatus = "off"

    @ObservationIgnored private let tap = SpikeEventTap()
    @ObservationIgnored private var pendingMode: SpikeEventTap.Mode?
    @ObservationIgnored private var watchdog: Timer?
    @ObservationIgnored private var blurPanel: NSPanel?
    @ObservationIgnored private var notchStrip: NSPanel?
    @ObservationIgnored private var feedbackSound: NSSound?

    private init() {
        let version = ProcessInfo.processInfo.operatingSystemVersionString
        SpikeLog.write("---- spike session started, macOS \(version) ----")
    }

    // MARK: - Experiments 1 and 2: event tap

    func startTap(_ mode: SpikeEventTap.Mode) {
        stopTap()
        logPermissions(context: "'\(mode.rawValue)' chosen")
        startWatchdog()

        if AXIsProcessTrusted() {
            install(mode)
            return
        }

        // Not trusted yet: ask, then install the moment trust appears (no relaunch).
        pendingMode = mode
        tapStatus = "waiting for Accessibility (\(mode.rawValue))"
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        SpikeLog.write("permissions: requested Accessibility with prompt; trusted now=\(trusted)")
    }

    func stopTap() {
        pendingMode = nil
        watchdog?.invalidate()
        watchdog = nil
        if tap.isInstalled { tap.remove() }
        tapStatus = "off"
    }

    private func install(_ mode: SpikeEventTap.Mode) {
        pendingMode = nil
        if mode == .consume { logDisplayServices() }
        if tap.install(mode) {
            tapStatus = mode.rawValue
        } else {
            tapStatus = "FAILED to create (\(mode.rawValue))"
        }
        logPermissions(context: "after install")
    }

    /// Once a second: start a pending tap when trust appears, drop the tap if
    /// trust is revoked (a live tap in an untrusted process can stall input),
    /// and re-enable it if the system switched it off.
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.watchdogTick() }
        }
    }

    private func watchdogTick() {
        let trusted = AXIsProcessTrusted()
        if let pendingMode {
            guard trusted else { return }
            SpikeLog.write("permissions: Accessibility granted; installing tap without relaunch")
            install(pendingMode)
        } else if tap.isInstalled {
            if !trusted {
                SpikeLog.write("permissions: Accessibility revoked while tap installed; removing tap")
                tap.remove()
                tapStatus = "off (Accessibility revoked)"
            } else if !tap.isEnabled {
                SpikeLog.write("tap: found disabled by watchdog; re-enabling")
                tap.reenable()
            }
        }
    }

    private func logPermissions(context: String) {
        let accessibility = AXIsProcessTrusted()
        let listen = CGPreflightListenEventAccess()
        let post = CGPreflightPostEventAccess()
        SpikeLog.write(
            "permissions (\(context)): AXIsProcessTrusted=\(accessibility) "
                + "CGPreflightListenEventAccess(InputMonitoring)=\(listen) "
                + "CGPreflightPostEventAccess=\(post)")
    }

    private func logDisplayServices() {
        let loaded = DisplayServicesBridge.isFrameworkLoaded
        let symbols = DisplayServicesBridge.symbolReport
            .map { "\($0.name)=\($0.isResolved ? "resolved" : "MISSING")" }
            .joined(separator: " ")
        let display = SpikeDisplay.targetDisplay()
        let canChange = DisplayServicesBridge.canChangeBrightness(display)
        var brightness: Float = -1
        let status = DisplayServicesBridge.getBrightness(display, into: &brightness)
        SpikeLog.write("displayservices: dlopen=\(loaded ? "ok" : "FAILED") \(symbols)")
        SpikeLog.write(
            "displayservices: display=\(display) builtin=\(CGDisplayIsBuiltin(display) != 0) "
                + "canChange=\(canChange.map { "\($0)" } ?? "nil") "
                + "getStatus=\(status.map { "\($0)" } ?? "nil") brightness=\(brightness)")
    }

    // MARK: - Experiment 3: blur test panel

    func toggleBlurPanel() {
        if let blurPanel {
            blurPanel.orderOut(nil)
            self.blurPanel = nil
            SpikeLog.write("blur: panel hidden")
            return
        }
        let panel = SpikePanels.makeBlurPanel()
        panel.orderFrontRegardless()
        blurPanel = panel
        let frame = panel.frame
        SpikeLog.write("blur: panel shown frame=\(frame) level=\(panel.level.rawValue)")
    }

    // MARK: - Experiment 4: notch-level test strip

    func toggleNotchStrip() {
        if let notchStrip {
            notchStrip.orderOut(nil)
            self.notchStrip = nil
            SpikeLog.write("notch: strip hidden")
            return
        }
        guard let panel = SpikePanels.makeNotchStrip() else { return }
        panel.orderFrontRegardless()
        notchStrip = panel
        let frame = panel.frame
        SpikeLog.write("notch: strip shown; frame after ordering front=\(frame)")
    }

    // MARK: - Experiment 5: feedback sound

    private static let feedbackSoundCandidates = [
        "/System/Library/LoadableBundles/BezelServices.loadbundle/Contents/Resources/volume.aiff",
        "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff",
    ]
    private static let feedbackPreferenceKey = "com.apple.sound.beep.feedback"

    func playFeedbackSound() {
        let fileManager = FileManager.default
        for path in Self.feedbackSoundCandidates {
            let exists = fileManager.fileExists(atPath: path)
            SpikeLog.write("sound: candidate \(exists ? "EXISTS" : "missing") \(path)")
        }

        let globalValue = CFPreferencesCopyValue(
            Self.feedbackPreferenceKey as CFString,
            kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let defaultsValue = UserDefaults.standard.object(forKey: Self.feedbackPreferenceKey)
        let globalText = globalValue.map { "\($0)" } ?? "not set"
        let defaultsText = defaultsValue.map { "\($0)" } ?? "not set"
        SpikeLog.write(
            "sound: \(Self.feedbackPreferenceKey) global domain=\(globalText) "
                + "via UserDefaults=\(defaultsText)")

        guard let path = Self.feedbackSoundCandidates.first(where: fileManager.fileExists(atPath:))
        else {
            SpikeLog.write("sound: no feedback sound file found")
            return
        }
        guard let sound = NSSound(contentsOfFile: path, byReference: true) else {
            SpikeLog.write("sound: NSSound could not load \(path)")
            return
        }
        feedbackSound = sound
        let started = sound.play()
        SpikeLog.write("sound: playing \(path) started=\(started) duration=\(sound.duration)s")
    }
}
#endif
