# ModernMac — Product and Technical Spec

Status: v1 plan, agreed 2026-11-10. This file is the source of truth for scope and design. When something on the real machine contradicts it, record the finding in `docs/FINDINGS.md`, then update this file in the same commit.

## 1. What we are building

ModernMac is a menu bar utility for macOS 14 and 15 that replaces the large, centre-screen volume and brightness overlay with a modern HUD. The user picks one of three styles:

| Style id | Name in UI | One-line description |
|---|---|---|
| `tahoe` | macOS 26 | Small glass capsule in the upper-right, just below the menu bar. Default. |
| `notch` | Notch | The notch widens; icon in the left wing, level in the right wing. |
| `circular` | Circular | Glass disc with a progress ring around the icon. |

Reference product: MediaMate (replacement volume/brightness HUDs, notch integration, macOS 13+). We are building the HUD-replacement part only.

### Decisions already made

| Topic | Decision | Consequence |
|---|---|---|
| Minimum OS | macOS 14.0 | `@Observable`, `SettingsLink`, modern spring and keyframe animation APIs are allowed. |
| Takeover strategy | Intercept media keys with an event tap, apply the change ourselves, draw our own HUD | Needs Accessibility permission. The stock HUD never appears because macOS never sees the key. |
| v1 extra | Interactive slider (hover keeps the HUD open, drag sets the level) | HUD panel must accept mouse events without activating the app. |
| Build | XcodeGen (`project.yml`) + `xcodebuild`, driven through a `Makefile` | `.xcodeproj` is generated and git-ignored. Never hand-edit a pbxproj. |
| Distribution | Direct (outside the Mac App Store), not sandboxed | Required by the event tap and the private brightness API. |

### Non-goals for v1

Keyboard backlight HUD. DDC/CI brightness for non-Apple external monitors. Now Playing. Touch Bar slider support (those do not send key presses). The real Liquid Glass API (`glassEffect`, macOS 26 SDK only) — we emulate the look. Officially supporting macOS 26+ (the app may run there, but it is not a target and is not tested). Mac App Store distribution.

## 2. Things to verify on the real Mac before building on them

These are believed true from documentation and from how comparable apps work, but they decide the architecture, so Phase 0 proves each one with a throwaway spike and writes the result to `docs/FINDINGS.md`.

**Phase 0 result (2026-11-11, macOS 15.7.8, MacBook Air M2):** V1, V2, V5, V6 and V7 confirmed. V3: `DisplayServicesBrightnessChanged` does not exist and is not needed. V4: the sound file is under `LoginPlugins`, and the preference key was not found. V8: stock plays the sound on every step, repeats included. V9: both volume keys unmute and step. The sections below already reflect this; details and exact values are in `docs/FINDINGS.md`.

| Id | Claim to verify | If false |
|---|---|---|
| V1 | Volume, mute and brightness keys arrive as `NX_SYSDEFINED` (CGEvent type 14) events with subtype 8 on this keyboard | Log what actually arrives (some keyboards send plain key-down codes 144/145 for brightness) and handle that form too. |
| V2 | Returning `nil` from an active session event tap for those events stops macOS from changing the level and from showing the stock HUD, on this OS version | Stop and report. Fallback design is "observe changes + suspend `OSDUIHelper`" and needs a new decision. |
| V3 | `DisplayServicesGetBrightness`, `DisplayServicesSetBrightness`, `DisplayServicesCanChangeBrightness` resolve via `dlsym` and work on the built-in display; `DisplayServicesBrightnessChanged` exists | Report which symbols are missing; do not guess alternatives silently. |
| V4 | The stock volume feedback sound file exists at `/System/Library/LoadableBundles/BezelServices.loadbundle/Contents/Resources/volume.aiff`, and the user preference is `com.apple.sound.beep.feedback` in the global domain | Locate the real path with `find /System/Library -name "volume.aiff"`; if none, ship without feedback sound. |
| V5 | An `NSVisualEffectView` with `.behindWindow` blending blurs desktop content inside a borderless transparent `NSPanel` | Try SwiftUI `Material`; report which one gives a real behind-window blur. |
| V6 | A panel at `NSWindow.Level.mainMenu + 3` draws over the menu bar strip beside the notch | Find the lowest level that does and record it. |
| V7 | Accessibility permission alone is enough for an active tap (no separate Input Monitoring grant) | Add the second permission to onboarding. |
| V8 | When the stock HUD plays the feedback sound: on key down, on key up, or on repeats | Match whatever is observed. |
| V9 | What stock macOS does when volume up or volume down is pressed while muted (unmute or stay muted, change the level or not) | Match whatever is observed and correct the routing table in §4.2. |

## 3. Architecture

```
┌────────────┐  key event   ┌──────────────┐  intent    ┌──────────────────┐
│ MediaKeyTap│ ───────────▶ │  KeyRouter   │ ─────────▶ │ AudioController  │
│ (CGEventTap│  consume /   │ (pure logic: │            │ BrightnessCtrl   │
│  on main   │  pass through│  key+mods →  │ ◀───────── │ (protocols)      │
│  run loop) │ ◀─────────── │  action)     │   result   └──────────────────┘
└────────────┘              └──────┬───────┘
                                   │ HUDState
                                   ▼
                           ┌───────────────┐      ┌─────────────────────────┐
                           │ HUDCoordinator│ ───▶ │ HUDPanel + HUDRootView  │
                           │ (show / hold /│      │ → Tahoe / Notch /       │
                           │  hide timers) │ ◀─── │   Circular style views  │
                           └───────────────┘ drag └─────────────────────────┘
```

Rules that keep this testable: `KeyRouter`, step maths, `HUDCoordinator` and settings are pure Swift with no AppKit, CoreAudio or private-API imports; hardware sits behind `VolumeControlling` and `BrightnessControlling` protocols with fakes in the test target; UI and coordinator are `@MainActor`.

### Repository layout

```
ModernMac/
├─ CLAUDE.md
├─ Makefile
├─ project.yml                  # XcodeGen
├─ Config/Base.xcconfig         # ad-hoc signing defaults; includes Local.xcconfig when present
├─ Config/Local.xcconfig        # git-ignored: DEVELOPMENT_TEAM, signing identity (template: Local.xcconfig.example)
├─ docs/  SPEC.md  PROMPTS.md  FINDINGS.md  reference/   (screenshots from Ando)
├─ App/   ModernMacApp.swift  AppDelegate.swift  Log.swift  Info.plist  ModernMac.entitlements  Assets.xcassets
├─ Sources/
│  ├─ Core/      MediaKey.swift  KeyRouter.swift  StepMath.swift  HUDState.swift  AppSettings.swift
│  │             HardwareControlling.swift (protocols)  KeyEventHandler.swift (route → apply → consume or pass)
│  ├─ Input/     MediaKeyTap.swift  PermissionManager.swift
│  ├─ Audio/     AudioController.swift  FeedbackSound.swift
│  ├─ Display/   BrightnessController.swift  DisplayServicesBridge.swift  ScreenGeometry.swift
│  ├─ HUD/       HUDCoordinator.swift  HUDPanel.swift  HUDRootView.swift
│  │             PlaceholderHUD.swift (Phase 1 text panel; removed in Phase 2)
│  │             Components/ GlassBackground.swift  LevelBar.swift  HUDIcon.swift
│  │             Styles/ TahoeHUDView.swift  NotchHUDView.swift  CircularHUDView.swift
│  ├─ Settings/  SettingsView.swift  OnboardingView.swift  MenuBarContent.swift
│  └─ Debug/     SimulateURLHandler.swift  SnapshotRenderer.swift      # DEBUG only
└─ Tests/        KeyRouterTests  StepMathTests  HUDCoordinatorTests  MediaKeyParsingTests
                 KeyEventHandlerTests  HUDStateTests  Fakes/
```

Identifiers: app name `ModernMac`, bundle id `com.ando.ModernMac` (change freely before first release), logging subsystem equal to the bundle id, URL scheme `modernmac` (DEBUG builds only).

## 4. Takeover engine

### 4.1 Event tap

Create with `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: 1 << 14, …)` and add its source to the main run loop in common modes. Decode by converting to `NSEvent` and reading `subtype == 8` and `data1`:

```
keyCode   = (data1 & 0xFFFF0000) >> 16
keyFlags  =  data1 & 0x0000FFFF
isDown    = ((keyFlags & 0xFF00) >> 8) == 0x0A
isRepeat  =  (keyFlags & 0x1) == 1
```

Key codes (from `IOKit/hidsystem/ev_keymap.h`): sound up 0, sound down 1, brightness up 2, brightness down 3, mute 7, illumination up 21, illumination down 22, illumination toggle 23, play 16, next 17, previous 18.

Observed in Phase 0: key state `0x0A` = down, `0x0B` = up (e.g. volume up `data1` = `0x00a00` / `0x00b00`). On the built-in keyboard, brightness keys arrive in this form too; there are no plain key-downs 144/145. The same event mask also delivers other type-14 subtypes (7, 18, 19) that have nothing to do with these keys. Everything that is not subtype 8 must pass through untouched.

Requirements for the tap:

1. The callback does no slow work. It decodes, asks `KeyRouter` for a decision, performs the hardware call (both are sub-millisecond), and returns. macOS disables taps that stall.
2. On `.tapDisabledByTimeout` or `.tapDisabledByUserInput`, re-enable with `CGEvent.tapEnable` and log it.
3. A 5-second health timer checks `CGEvent.tapIsEnabled` and re-enables if needed; also re-check after `NSWorkspace.didWakeNotification`.
4. If `AXIsProcessTrusted()` turns false while running (polled every 2 s), remove the tap at once. A live tap in a process that lost trust can stall input system-wide.
5. For a consumed key, consume its key-up as well so the system never sees half a press.

**Fail-open principle.** The user must never lose their volume or brightness keys because of us. Whenever we cannot do the job — permission missing, no controllable device, a hardware call returns an error, the feature toggle is off — the event is passed through untouched and the stock HUD does its thing. If ModernMac crashes or quits, the tap dies with the process and macOS takes over automatically; no cleanup is needed.

### 4.2 Key routing table

Steps are on a grid, matching the system: normal step = 1/16, fine step = 1/64. New level = `clamp((round(current × grid) ± 1) / grid, 0…1)`.

| Key | Modifiers | Action | Event |
|---|---|---|---|
| Volume up / down | none | ±1/16. While muted: unmute **and** step, for both up and down (observed in V9). | consume |
| Volume up / down | ⇧⌥ | ±1/64 | consume |
| Volume up / down | ⇧ only | ±1/16 and invert the feedback-sound preference for this press | consume |
| Mute | none or ⇧ | toggle mute | consume |
| Volume or mute | ⌥ only | nothing (macOS opens Sound settings) | pass through |
| Brightness up / down | none | ±1/16 on the target display | consume |
| Brightness up / down | ⇧⌥ | ±1/64 | consume |
| Brightness up / down | ⌥ only, or any ⌃ | nothing (macOS opens Displays settings / adjusts an external display) | pass through |
| Illumination keys, play, next, previous, anything else | any | nothing | pass through |

Key repeat counts as another step. If the output device has no settable volume, or the target display is not controllable, the key is passed through (fail-open) rather than swallowed.

Only ⇧, ⌥, ⌃ and ⌘ take part in routing; caps lock and fn are ignored. **Every combination not listed above passes through.** That covers volume or mute with ⌃ or ⌘, mute with ⇧⌥, brightness with ⇧ only, and brightness with ⌘ (macOS uses ⌘ + brightness for display mirroring). `KeyRouter` implements exactly this table; `KeyEventHandler` applies the action and consumes the event only if the hardware call succeeded.

In Debug builds every key event and its outcome is appended to `~/Library/Logs/ModernMac/trace.log`.

### 4.3 Volume (CoreAudio / AudioToolbox, public API)

Default output device: `kAudioHardwarePropertyDefaultOutputDevice` on `kAudioObjectSystemObject`. Level: `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`, output scope, main element, `Float32` 0…1 — this is the same scale the system slider uses. Mute: `kAudioDevicePropertyMute`, output scope. Check `AudioObjectHasProperty` and `AudioObjectIsPropertySettable` before trusting either.

Register property listeners for default-device change, level and mute so cached state, device name and icon stay correct when something else changes them. External changes update a visible HUD but do not open one (the stock HUD also only opens for keys).

Icon selection: muted or level 0 → `speaker.slash.fill`; otherwise `speaker.wave.3.fill` with `variableValue: level`. If the device name contains "AirPods Max" / "AirPods Pro" / "AirPods" use `airpodsmax` / `airpodspro` / `airpods`; other Bluetooth or headphone-port devices use `headphones`.

Feedback sound: play `/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff` (V4) through `NSSound` when (system feedback setting on) XOR (⇧ held). Play it on every volume step, which means each key-down, key repeats included, and never on key-up (V8). If the file is missing, play nothing.

The system setting ("Play feedback when volume is changed") is `com.apple.sound.beep.feedback` in the global domain (read with `CFPreferencesCopyValue`, any application, current user, any host), but macOS writes it only once the setting is first toggled. A missing key means **on**: the setting shows on and stock macOS plays the click (see `docs/FINDINGS.md` V4). Read it per keypress; a change in System Settings applies to the next press without relaunch.

The mute key plays no feedback sound.

### 4.4 Brightness (private API, loaded dynamically)

Load with `dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)` and `dlsym`, never by linking the framework. Signatures:

```c
int  DisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness);   // 0 = success
int  DisplayServicesSetBrightness(CGDirectDisplayID display, float brightness);    // 0…1
bool DisplayServicesCanChangeBrightness(CGDirectDisplayID display);
void DisplayServicesBrightnessChanged(CGDirectDisplayID display, double brightness); // optional; absent on macOS 15.7.8
```

All of this lives in `DisplayServicesBridge.swift` and nowhere else. Every symbol is optional. If Get, Set or CanChange is missing, `BrightnessController.isAvailable` is false and brightness keys pass through. `DisplayServicesBrightnessChanged` is the exception: it does not exist on macOS 15.7.8, and System Settings' Displays slider follows `SetBrightness` without it (V3), so its absence never disables brightness.

Target display: the display under the mouse pointer if it reports `CanChangeBrightness`; otherwise the built-in display (`CGDisplayIsBuiltin`) if present; otherwise none (pass through). After a successful set, call `DisplayServicesBrightnessChanged` only if it resolved.

### 4.5 Permissions

Accessibility is the only permission needed. In V7 the active tap worked while `CGPreflightListenEventAccess` (Input Monitoring) was false, so onboarding has no Input Monitoring step.

`PermissionManager` exposes `isTrusted` (from `AXIsProcessTrusted()`), `requestTrust()` (`AXIsProcessTrustedWithOptions` with the prompt option) and `openSettings()` (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`). While untrusted it polls once per second and starts the tap the moment trust appears — no relaunch.

Development note: macOS ties the Accessibility grant to the code signature. With ad-hoc signing every rebuild looks like a new app and the grant silently stops working. Sign Debug builds with a stable identity from `Config/Local.xcconfig` (an Apple Development certificate, or a self-signed code-signing certificate). If a grant gets stuck: `tccutil reset Accessibility com.ando.ModernMac`.

## 5. HUD system

### 5.1 State and coordinator

```swift
enum HUDKind { case volume, brightness }

struct HUDState: Equatable {
    var kind: HUDKind
    var level: Double        // 0…1
    var isMuted: Bool        // volume only
    var deviceName: String?  // output device or display name
    var symbolName: String
    var symbolValue: Double  // SF Symbols variableValue
}
```

`HUDCoordinator` phases: `hidden → visible → hidden`, with `visible` held open while the pointer hovers the HUD or a drag is in progress. Each key event restarts the hide timer (default 1.5 s, setting range 0.8–3.0 s). A different `kind` arriving while visible swaps content in place with a cross-fade; it does not hide and re-show. Time is injected (a clock protocol) so tests run instantly.

The coordinator publishes a `HUDPresentation` (visible flag, state, target display) through an `onChange` callback and keeps the last state after hiding so a style can fade out with content. `show` is for key events; `update` is for changes made elsewhere and only refreshes a visible HUD of the same kind, without restarting the timer. Leaving the HUD with the pointer restarts the full hide delay; a drag released outside the HUD hides after 0.8 s (§5.5).

Target screen: volume HUD → `NSScreen.main`, falling back to the screen under the pointer; brightness HUD → the screen of the display being adjusted.

### 5.2 Panel

One reusable `HUDPanel: NSPanel`: style mask `[.borderless, .nonactivatingPanel]`, non-opaque, clear background, `canBecomeKey` and `canBecomeMain` false, `hidesOnDeactivate` false, `isMovable` false, `animationBehavior = .none`, collection behaviour `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`. Level `.statusBar` for `tahoe` and `circular`; the level proven in V6 for `notch`. Content is an `NSHostingView` whose view accepts first mouse. Override `constrainFrameRect(_:to:)` to return the frame unchanged, otherwise AppKit pushes a panel out of the menu bar strip. `mainMenu + 3` (raw 27) draws over the menu bar beside the notch (V6).

Behavioural requirements (acceptance-tested by hand):

- Showing the HUD never steals focus, never deactivates the frontmost app, and works over full-screen apps and on every Space.
- A click one point outside the visible shape reaches the app underneath. While hidden, the panel ignores all mouse events.
- With "Interactive" off, the panel always ignores mouse events.

### 5.3 Glass

`GlassBackground` wraps `NSVisualEffectView` (`blendingMode = .behindWindow`, `state = .active`, material `.popover` so it follows light/dark), clipped to the shape with a continuous corner curve. On top: a 1 pt rim stroke with a top-to-bottom gradient (white 35% → white 6%), and a soft shadow (radius 18, y 6, black 18%). It takes a rendering mode from the environment: `.live` uses the visual-effect view; `.snapshot` substitutes a flat translucent tint, because offscreen rendering cannot capture a behind-window blur.

### 5.4 Style specifications

All numbers are in points and are starting values. Final tuning is done against the screenshots Ando places in `docs/reference/`; when a screenshot and a number here disagree, the screenshot wins and this table is updated.

**`tahoe` — macOS 26 look.** Public descriptions of the real thing: a smaller, oblong, notification-like overlay at the upper-right, just below the menu bar.

| Property | Value |
|---|---|
| Shape | Capsule, 280 × 44. With "Show device name" on: continuous rounded rectangle 280 × 64, radius 22, name label (12 pt medium, secondary) above the bar row. |
| Content | Leading SF Symbol 17 pt semibold, then `LevelBar` filling the rest. Horizontal padding 16, spacing 12. Optional trailing percentage, 12 pt monospaced digits. |
| Level bar | Capsule track 6 high, primary colour at 20% opacity; fill in primary. No knob. On hover (interactive) the bar grows to 10 high. |
| Position | Top-right of the target screen: 10 below `visibleFrame.maxY`, 10 from the right edge. Setting allows top-left, top-centre, bottom-centre. Note: on the notched screen `visibleFrame.maxY` is 37 below the top while the menu bar is 32 high, so the visible gap to the menu bar is 15; tune against the reference screenshots. |
| Appear | Opacity 0→1, scale 0.9→1 anchored top-trailing, offset y −8→0; spring response 0.35, damping 0.8. |
| Disappear | Opacity →0, scale →0.95; 0.2 s ease-out. |
| Level change | Fill animates with a 0.12 s ease-out; the symbol's variable value updates without animation. |

**`notch` — integrated with the notch.**

| Property | Value |
|---|---|
| Eligibility | Screens where `NSScreen.safeAreaInsets.top > 0`. |
| Geometry | `notchHeight = safeAreaInsets.top`; `notchWidth = frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width`; horizontally centred, flush with the top of the screen. Ando's MacBook Air: 179 × 32 at x 646…825 on a 1470-wide screen. Never use `NSStatusBar.thickness` for this; it reports 22 on the notched screen. |
| Collapsed | Exactly the notch rectangle, pure black: invisible. The panel is ordered out when collapsed and idle. |
| Expanded | Same height, widened by a 68-wide wing on each side. Pure black fill, bottom corners radius 10 continuous, top corners square. |
| Content | Left wing: symbol 14 pt, white. Right wing: mini level bar 44 × 5 (white fill, white 25% track), or percentage text if the setting says so. |
| Appear / disappear | Width animates with spring response 0.4, damping 0.75; wing content fades in 0.08 s after the expansion starts and fades out before the collapse. |
| Interactive | On hover, a 30-high drawer drops below the expanded shape with a full-width `LevelBar` that can be dragged. Build this last in the notch phase. |
| Screens without a notch | A black floating pill of the same expanded size, centred, 8 below the top of `visibleFrame`, same content and animations (scale + fade instead of width). |

**`circular` — ring.**

| Property | Value |
|---|---|
| Shape | Glass disc, diameter 84. |
| Ring | Inset 9, line width 6, round caps; track primary at 18%; progress in primary, starting at 12 o'clock, clockwise. |
| Content | Centred symbol 26 pt. Optional percentage under it (10 pt, monospaced digits). |
| Position | Same rule and setting as `tahoe`. |
| Appear / disappear | Scale 0.6→1 with opacity, spring response 0.35, damping 0.7; reverse to 0.8 on exit, 0.2 s. |
| Level change | Ring trim animates 0.15 s ease-out. |
| Interactive | Vertical drag or scroll over the disc: 1 pt = 0.5%. Hover scales to 1.06. |

Shared rules: muted shows the slashed speaker and an empty bar or ring; respect Reduce Motion (cross-fade only, no scale or slide) and Increase Contrast (opaque background, stronger rim); every style renders correctly in light and dark appearance, except `notch`, which is always black with white content.

### 5.5 Interactive slider

Dragging maps pointer position to level continuously (no grid snapping), calls the same controller the keys use, throttled to at most one hardware write per 16 ms, and keeps the HUD open until 0.8 s after mouse-up. No feedback sound during a drag; one on release for volume, following the preference.

## 6. App shell

Agent app (`LSUIElement = true`), SwiftUI lifecycle with an `NSApplicationDelegateAdaptor`. Scenes: `MenuBarExtra` (toggleable) and `Settings`. Opening Settings from an agent app needs `NSApp.activate(ignoringOtherApps: true)` alongside `SettingsLink` / `openSettings`, otherwise the window opens behind other apps.

Menu bar menu: enabled toggle, current style picker, "Settings…", permission status line when not trusted, "Quit ModernMac".

Onboarding window (shown at launch while untrusted): what the app does, why Accessibility is needed, a button that requests trust and opens the right Settings pane, a live status indicator that flips to granted on its own, then a "try your volume keys" confirmation.

Settings (stored in `UserDefaults`, exposed through one `@Observable AppSettings`):

| Key | Type | Default |
|---|---|---|
| `isEnabled` | Bool | true |
| `handleVolume` / `handleBrightness` | Bool | true / true |
| `style` | `tahoe` \| `notch` \| `circular` | `tahoe` |
| `position` | `topRight` \| `topLeft` \| `topCenter` \| `bottomCenter` | `topRight` |
| `hideDelay` | Double, 0.8–3.0 | 1.5 |
| `isInteractive` | Bool | true |
| `showPercentage` / `showDeviceName` | Bool | false / false |
| `playFeedbackSound` | `followSystem` \| `always` \| `never` | `followSystem` |
| `showMenuBarIcon` | Bool | true |
| launch at login | via `SMAppService.mainApp` status, not stored | off |

The Settings window has a live preview: the real style views rendered in `.snapshot` mode over a sample backdrop, animating between a few levels.

## 7. Build, run and verification loop

`project.yml` defines the `ModernMac` application target (macOS 14.0, Swift language mode 5, hardened runtime, no sandbox, includes `Config/Local.xcconfig` if present) and `ModernMacTests`. All work goes through the Makefile so commands stay stable:

| Command | Does |
|---|---|
| `make gen` | `xcodegen generate` |
| `make build` | gen + `xcodebuild -quiet -project ModernMac.xcodeproj -scheme ModernMac -configuration Debug -derivedDataPath .build/xcode -destination 'platform=macOS,arch=$(uname -m)' build` (the destination silences the arm64/x86_64 ambiguity) |
| `make test` | gen + same with `test` |
| `make run` | build, kill any running copy, `open` the built app |
| `make kill` | `pkill -x ModernMac` (ignore "no process"), then wait until the process is gone so `make run` never re-activates the old copy |
| `make logs` | `log stream --level debug --predicate 'subsystem == "com.ando.ModernMac"'` |
| `make simulate ARGS="kind=volume&level=0.6"` | `open "modernmac://simulate?$(ARGS)"` |
| `make snapshots` | build, then run the binary with `--snapshots .build/snapshots` |

Debug-only hooks, compiled out of Release:

- **Simulate URL.** `modernmac://simulate?kind=volume|brightness&level=0…1&muted=0|1&style=tahoe|notch|circular&hold=<seconds>` drives `HUDCoordinator` exactly as a key press would, without touching hardware. This lets the HUD be exercised from the terminal.
- **Snapshot mode.** `ModernMac --snapshots <dir>` renders every style × kind × level {0, 0.33, 0.66, 1} + muted × {light, dark} to `@2x` PNGs with `ImageRenderer` over a bundled gradient backdrop, then exits 0. Claude Code reads these PNGs to review its own visual work before asking Ando to look.

What only Ando can verify: pressing physical keys, the Accessibility grant, the stock HUD not appearing, how the blur and animation feel. Each phase ends with a short checklist for him.

## 8. Phases

Each phase ends with: `make test` green, a commit, an update to `docs/FINDINGS.md` if anything surprising came up, and a stop for Ando's manual check.

| # | Phase | Outcome | Gate |
|---|---|---|---|
| 0 | Environment and feasibility | Tooling checked; project scaffolded; agent app builds and runs; spike proves V1–V9 | Ando confirms: with the spike running, volume and brightness keys change the level through us and the stock HUD does not appear. |
| 1 | Engine | `MediaKeyTap`, `KeyRouter`, `StepMath`, `AudioController`, `BrightnessController`, `PermissionManager`, `HUDCoordinator`, fakes and unit tests; a plain placeholder HUD | Every row of the routing table works on the real keyboard; quitting the app restores stock behaviour instantly. |
| 2 | HUD infrastructure + `tahoe` | `HUDPanel`, `GlassBackground`, `LevelBar`, `HUDIcon`, `TahoeHUDView`, simulate URL, snapshot mode, interactive slider | Looks right against `docs/reference/`; never steals focus; works over a full-screen app. |
| 3 | `notch` | `ScreenGeometry`, `NotchHUDView`, pill fallback, hover drawer | Wings align with the physical notch to the pixel; correct on an external display. |
| 4 | `circular` | `CircularHUDView` with drag and scroll | Ring tracks the level smoothly at key-repeat speed. |
| 5 | App shell | Onboarding, Settings with live preview, menu bar menu, launch at login | Fresh-install flow works from zero permissions to working HUD without a relaunch. |
| 6 | Hardening and release | Sleep/wake, display hot-plug, device switching, permission revoked while running, Reduce Motion, Increase Contrast, README, Release build script | The test matrix in §9 passes. |

## 9. Hardening test matrix

Switch output device while the HUD is visible (speakers → Bluetooth → HDMI without volume control). Hold a key for five seconds. Alternate volume and brightness quickly. Sleep and wake, then press a key. Plug and unplug an external display with the HUD visible. Close the lid with an external display attached (no notch any more). Full-screen video, Mission Control, a second Space. Revoke Accessibility while running; grant it again. Focus a password field (Secure Input) and press volume keys. Toggle light and dark appearance. Turn on Reduce Motion and Increase Contrast. Quit and force-quit the app, then confirm the stock HUD is back.

## 10. Risks

| Risk | Mitigation |
|---|---|
| Private brightness API changes in a future macOS | Dynamic loading with optional symbols; brightness falls back to pass-through; isolated in one file. |
| Event tap disabled by the system | Re-enable on the disabled callbacks plus the health timer; callback kept trivial. |
| Accessibility grant lost on every rebuild | Stable signing identity in `Local.xcconfig`. |
| Glass looks flat compared with real Liquid Glass | Tune rim, tint and shadow against reference screenshots; accept that refraction is not reproducible before macOS 26. |
| Notch geometry off by a pixel on some models | Compute from `NSScreen` APIs, never hard-code; verify on Ando's machine and log the numbers. |
| Licence contamination | SlimHUD and MewNotch are GPL-3.0. Do not copy code from them or from any GPL project. Techniques are fine; code is written fresh. |
