import AppKit
import SwiftUI

/// The app's two ordinary windows: Settings and onboarding.
///
/// They are plain AppKit windows with SwiftUI content, not SwiftUI scenes:
/// Settings has to open from the app delegate when the app is launched a
/// second time with its menu bar icon hidden, and a scene can only be opened
/// from inside a SwiftUI view, which may not exist then.
@MainActor
final class AppWindows: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let permissions: PermissionManager
    private let launchAtLogin: LaunchAtLogin
    private let onboardingProgress: OnboardingProgress

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    init(
        settings: AppSettings, permissions: PermissionManager,
        launchAtLogin: LaunchAtLogin, onboardingProgress: OnboardingProgress
    ) {
        self.settings = settings
        self.permissions = permissions
        self.launchAtLogin = launchAtLogin
        self.onboardingProgress = onboardingProgress
    }

    var isOnboardingVisible: Bool { onboardingWindow?.isVisible ?? false }

    // MARK: - Settings

    func showSettings() {
        launchAtLogin.refresh()
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        bringToFront(window)
        Log.app.notice("Settings shown")
    }

    func makeSettingsWindow() -> NSWindow {
        let tabs = SettingsTabController()
        tabs.tabStyle = .toolbar
        for pane in SettingsPane.allCases {
            let host = NSHostingController(rootView: paneView(pane))
            // A pane can grow or shrink while it is showing (a hint appears
            // under a control); reporting its size lets the window follow.
            host.sizingOptions = [.preferredContentSize]
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: nil)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        tabs.fitWindowToSelectedTab(animated: false)
        window.center()
        return window
    }

    func paneView(_ pane: SettingsPane) -> SettingsPaneView {
        SettingsPaneView(
            pane: pane, settings: settings, permissions: permissions,
            launchAtLogin: launchAtLogin,
            showOnboarding: { [weak self] in self?.showOnboarding() })
    }

    // MARK: - Onboarding

    func showOnboarding() {
        if onboardingWindow?.isVisible != true { onboardingProgress.reset() }
        let window = onboardingWindow ?? makeOnboardingWindow()
        onboardingWindow = window
        bringToFront(window)
        Log.app.notice("Onboarding shown")
    }

    func onboardingView() -> OnboardingView {
        OnboardingView(
            permissions: permissions, progress: onboardingProgress,
            close: { [weak self] in self?.onboardingWindow?.close() })
    }

    private func makeOnboardingWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: onboardingView()))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = "Welcome to ModernMac"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(window.contentViewController?.view.fittingSize ?? .zero)
        window.center()
        return window
    }

    // MARK: - Front

    /// An agent app is not active when one of its windows opens, so without
    /// this the window would open behind the frontmost app's windows.
    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Should the system turn the activation down, the window is still
        // put above the other apps' windows.
        window.orderFrontRegardless()
    }
}

/// Toolbar tabs like any macOS settings window. The window takes each
/// tab's title and resizes to its content, keeping its top edge in place.
final class SettingsTabController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindowToSelectedTab(animated: true)
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        guard tabViewItems.indices.contains(selectedTabViewItemIndex),
              tabViewItems[selectedTabViewItemIndex].viewController === viewController
        else { return }
        fitWindowToSelectedTab(animated: true)
    }

    func fitWindowToSelectedTab(animated: Bool) {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return }
        let item = tabViewItems[selectedTabViewItemIndex]
        guard let window = view.window, let content = item.viewController?.view else { return }
        window.title = item.label

        let size = content.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        var frame = window.frame
        frame.origin.y += frame.height - target.height
        frame.size = target
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }
}
