# ModernMac — Findings

What was actually observed on Ando's Mac. Where this file and `SPEC.md` disagree, this file wins and the spec gets corrected in the same commit.

## Environment (checked 2026-11-11)

| Item | Value |
|---|---|
| Mac | MacBook Air M2 (`Mac14,2`), arm64 |
| macOS | 15.7.8 (24G824) |
| Xcode | 26.3 (17C529), selected path `/Applications/Xcode.app/Contents/Developer` |
| Swift | 6.2.4 (project builds in language mode 5) |
| XcodeGen | 2.46.0, installed with Homebrew on 2026-11-11 |
| Signing identity | `Apple Development: andomihasina@gmail.com (9S8XMTXW9U)`, team `8H6L27L6R4`, expires 2027-02-20. The only code-signing identity on this Mac. |
| Displays | Built-in Liquid Retina only, 2560 × 1664 pixels (1470 × 956 pt at 2×), notched. No external display attached. |
| Audio output during tests | CoreAudio device id 72 (built-in speakers) |

Notes:

- Xcode 26.3 ships the macOS 26 SDK. The deployment target of 14.0 makes the compiler reject unguarded newer APIs, which is what enforces "no macOS 26 APIs".
- The repository root is `modernmac/modernmac` (the outer `modernmac` folder is just a container). It was already a git repository with `origin` set, so Phase 0 did not run `git init`.
- The very first `codesign` call with the Apple Development key failed with `errSecInternalComponent`; the retry a minute later succeeded and every build since has signed cleanly. Most likely a one-time keychain access prompt for the private key. If it comes back: unlock the login keychain and answer "Always Allow".
- `xcodebuild` warns about multiple matching destinations (arm64 and x86_64) unless one is given, so the Makefile passes `-destination 'platform=macOS,arch=$(uname -m)'`.

## How the spike was run

Debug build, menu bar extra → "Spike (Phase 0)" items, 2026-11-11 18:50–18:58. The spike writes every line to `~/Library/Logs/ModernMac/spike.log` as well as the unified log; the values below are copied from that file. Visual and audible results are Ando's reports.

## Results

| Id | Result | Summary |
|---|---|---|
| V1 | Confirmed | All five keys arrive as type 14, subtype 8. No plain key codes 144/145. |
| V2 | Confirmed | Consuming the events stops both the level change and the stock HUD. |
| V3 | Partly true | Get, Set and CanChange work. `DisplayServicesBrightnessChanged` does not exist, and is not needed. |
| V4 | Path wrong; preference not found | The file lives under `LoginPlugins`, not `LoadableBundles`. `com.apple.sound.beep.feedback` is not set anywhere. |
| V5 | Confirmed | Behind-window blur works in a borderless transparent non-activating panel; SwiftUI `Material` too. |
| V6 | Confirmed | Level `mainMenu + 3` (27) draws over the menu bar next to the notch. |
| V7 | Confirmed | Accessibility alone is enough for the active tap. |
| V8 | Observed | Stock plays the feedback sound on every step, including each key repeat while held. |
| V9 | Spec assumption wrong | While muted, volume up **and** volume down both unmute and move the level one step. |

### V1 — event format

Every press produced one key-down and one key-up, both `CGEventType` 14, `NSEvent.subtype` 8, decoded exactly as SPEC §4.1 describes:

| Key | Key code | data1 down | data1 up |
|---|---|---|---|
| Volume up | 0 | `0x00a00` | `0x00b00` |
| Volume down | 1 | `0x10a00` | `0x10b00` |
| Brightness up | 2 | `0x20a00` | `0x20b00` |
| Brightness down | 3 | `0x30a00` | `0x30b00` |
| Mute | 7 | `0x70a00` | `0x70b00` |

- Key state byte: `0x0A` = down, `0x0B` = up.
- `CGEventFlags` on every subtype-8 event was `0x100` (`NX_NONCOALSESCEDMASK` only, no modifiers). Modifier combinations (⇧, ⇧⌥, ⌥, ⌃) were not exercised; Phase 1 must check them against the routing table.
- **Not observed: the repeat bit.** All 80 subtype-8 events had `repeat=false`; no key was held long enough during the tap runs. V8 shows that stock macOS does repeat these keys, so Phase 1 must hold each key and confirm how repeats arrive (`keyFlags & 0x1`) before relying on it.
- Brightness keys on this keyboard never arrived as plain key-downs 144/145; nothing needs to handle that form here.
- Other type-14 subtypes arrive through the same mask and must pass through untouched: subtype 7 (`data1=0x1`, `data2` toggling 1/0, 74 events, not tied to any key press — mouse/trackpad button state) and subtypes 18/19 (`data1=0`, a few events). The spike passes everything that is not subtype 8.
- The "log only" run (listen-only tap, mask `0x4c00`) was installed 18:58:15–18:58:31 and recorded no key presses; it was not needed, because the consume run already logged every event.

### V2 — consuming the keys

With the active tap (`.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap`, mask `0x4000`) returning `nil` for the key-down and the matching key-up:

- Ando: the stock HUD never appeared, not even briefly. Levels changed only through ModernMac.
- Each press moved exactly one 1/16 step; no double steps. Examples from the log:
  - volume `0.125 → 0.1875` (up), `0.1875 → 0.125` (down), four quick presses `0.125 → 0.1875 → 0.25 → 0.3125 → 0.375`;
  - brightness `0.875 → 0.9375 → 1.0` and back; brightness up at `1.0` stays `1.0` (clamped).
- Read-back after each set matched the target to within float rounding (`0.18750001`, `0.37500003`, `0.9375001`).
- Mute toggled `false → true → false`, set ok, read-back matching.
- The tap was never disabled by timeout or user input during the session.
- Not explicitly confirmed: that the stock HUD came back after "Tap: off". The V8/V9 observations were made with the tap off and stock behaviour working, which implies it.

### V3 — DisplayServices

- `dlopen` of `/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices` succeeds.
- Resolved: `DisplayServicesGetBrightness`, `DisplayServicesSetBrightness`, `DisplayServicesCanChangeBrightness`.
- **Missing: `DisplayServicesBrightnessChanged`.** It is not in the framework's export list on macOS 15.7.8.
- Built-in display (id 1): `CanChangeBrightness` = true, every `GetBrightness` and `SetBrightness` returned 0.
- Ando: the System Settings → Displays brightness slider followed the keys without the missing notification call. The Sound slider followed the volume keys too.
- Other brightness exports, for reference if something is needed later (all prefixed `DisplayServices`): `CreateBrightnessTable`, `GetBrightnessButtonsEnabled`, `GetBrightnessIncrement`, `GetLinearBrightness`, `GetLinearBrightnessUsableRange`, `HasBrightnessButtons`, `NeedsBrightnessSmoothing`, `RegisterForBrightnessChangeNotifications`, `SetBrightnessButtonsEnabled`, `SetBrightnessSmooth`, `SetBrightnessWithType`, `SetLinearBrightness`, `UnregisterForBrightnessChangeNotifications`. None of these is used.

### V4 — feedback sound

- `/System/Library/LoadableBundles/BezelServices.loadbundle/Contents/Resources/volume.aiff` does not exist.
- The real file, the only `volume.aiff` under `/System/Library`: `/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff`. `NSSound` plays it (duration 0.382 s); Ando reported the playback as OK.
- `com.apple.sound.beep.feedback` is **not set**: not in the global domain (`defaults read -g`, `CFPreferencesCopyValue` with `kCFPreferencesAnyApplication`), not in the current-host global domain, and not in any plist under `~/Library/Preferences` or `ByHost`. This was true both at 18:56:57 and after the V8 test, during which stock macOS played the sound. The only related global keys are `com.apple.sound.beep.flash = 0` and `com.apple.sound.beep.sound = /System/Library/Sounds/Submarine.aiff`.
- **Settled in Phase 1 (2026-11-12):** after Ando switched the setting on in System Settings, `CFPreferencesCopyValue("com.apple.sound.beep.feedback", AnyApplication, CurrentUser, AnyHost)` read `true` on the next keypress (07:56:53); after switching it off it read `false` (08:00:39). No relaunch needed. So the key *is* where the spec said, but macOS writes it only on the first toggle. Before that it was absent while the setting showed on and stock macOS clicked (V8), so **absent = on**.

### V5 — blur in a panel

Blur test panel: borderless, `.nonactivatingPanel`, non-opaque, clear background, level `.statusBar` (25), three 280 × 44 capsules:

- A: `NSVisualEffectView`, `.behindWindow`, `.active`, material `.popover`, clipped with `maskImage`;
- B: the same, clipped with a layer corner radius (continuous curve);
- C: SwiftUI `Capsule().fill(.ultraThinMaterial)`.

Ando: all three looked good over desktop content. Spec §5.3 (`NSVisualEffectView`, behind-window) stands. A finer comparison between A and B can wait for the real `GlassBackground` in Phase 2.

### V6 — notch level and geometry

Built-in screen, logged values (points):

| Value | Observed |
|---|---|
| `frame` | (0, 0, 1470, 956), backing scale 2.0 |
| `visibleFrame` | (0, 58, 1470, 861), so `visibleFrame.maxY` = 919 (37 below the top, Dock at the bottom) |
| `safeAreaInsets.top` | 32 |
| `auxiliaryTopLeftArea` | (0, 924, 646, 32) |
| `auxiliaryTopRightArea` | (825, 924, 645, 32) |
| Computed notch | width `1470 − 646 − 645 = 179`, height 32, spanning x 646…825 |
| `NSStatusBar.system.thickness` | 22 (does **not** match the 32-pt menu bar on this notched screen) |
| Window levels | `mainMenu` = 24, `statusBar` = 25, strip at 27 |

- The red 200 × 32 strip at x 635…835 was placed exactly where requested (overriding `constrainFrameRect` keeps AppKit from pushing it below the menu bar).
- Ando: red was visible on both sides of the notch, drawn over the menu bar, with the bottom edge aligned to the bottom of the menu bar. `mainMenu + 3` is enough; a lower level was not tried.
- For `notch` geometry use `safeAreaInsets` and the auxiliary areas, never `NSStatusBar.thickness`.
- `visibleFrame.maxY` is 5 pt lower than the menu bar's bottom edge (919 vs 924). Keep that in mind when placing the `tahoe` capsule "10 below `visibleFrame.maxY`".

### V7 — permissions

- Before the grant: `AXIsProcessTrusted` = false, `CGPreflightListenEventAccess` (Input Monitoring) = false, `CGPreflightPostEventAccess` = false.
- After Ando granted Accessibility, the watchdog installed the active tap within one second without a relaunch (granted 18:50:48.675, tap installed 18:50:48.705).
- With the active tap working: `AXIsProcessTrusted` = true, `CGPreflightListenEventAccess` = **false**, `CGPreflightPostEventAccess` = true. Accessibility alone is enough; no Input Monitoring step is needed in onboarding.
- Side note: right after installing the *listen-only* tap whose mask includes `keyDown`/`keyUp`, `CGPreflightListenEventAccess` read true. The shipping tap does not use that mask, so this does not matter for v1.

### V8 — when stock plays the feedback sound

Tap off, "Play feedback when volume is changed" on. Ando: the click plays at **every step, including each key repeat** while volume up is held. My inference, not separately observed: repeats are key-downs, so the sound belongs to the key-down (one per step), not the key-up.

### V9 — volume keys while muted (stock)

Tap off, sound muted, one press. Ando:

- Volume up: unmutes **and** raises the level one step.
- Volume down: unmutes **and** lowers the level one step.

The spec assumed down would stay muted. It does not.

## Phase 1 — takeover engine on the real keyboard (2026-11-11 / 12)

Ando walked the 16-step checklist with the Debug build; every step behaved as expected. Values below are from `~/Library/Logs/ModernMac/trace.log`.

### Key repeat (V1 open item, settled)

- Holding a key sends repeated key-downs with the repeat bit set: `data1 = 0x…a01` (e.g. `0xa01` for volume up), flags unchanged. Seen for volume up/down and brightness up/down (35 repeats in total).
- Repeat interval about 83 ms (19:29:00.582, .664, .749, .834 …).
- Each repeat is one step and plays feedback when on, matching V8. Key-up arrives once, at release.

### Modifier flags (raw `CGEventFlags` on the media-key event)

| Held | flags | Decoded | Result |
|---|---|---|---|
| none | `0x100` | — | consumed |
| ⇧ | `0x20102` | ⇧ | volume/mute consumed |
| ⌥ | `0x80120` | ⌥ | passed through; Sound settings opened |
| ⇧⌥ | `0xa0122` | ⇧⌥ | consumed, 1/64 steps (e.g. 0.828125 → 0.84375 → 0.859375) |
| ⌘ | `0x100108` | ⌘ | passed through (not in the table) |
| ⇧⌘ | `0x12010a` | ⇧⌘ | passed through (not in the table) |

- ⌥ + brightness and ⌃ + brightness produced **no event in the tap at all**: macOS acts on them before the session tap sees a subtype-8 event. They cannot be intercepted, so the router's pass-through for them is moot but harmless. Ando confirmed ⌥ + brightness opened Displays settings.

### Other observations

- Mute and ⇧ + mute toggle; the level is untouched. Volume up and down while muted unmute and step (07:55:27, 07:55:29), as in V9.
- Hardware returns float noise (0.9375001192…, 0.4999999701…); snapping to the grid keeps the next step exact.
- Brightness at 1.0 + up: a no-op step (1.0 → 1.0) is still consumed and shown, as intended.
- With "Enabled" off, all keys passed through and the stock HUD returned. Revoking Accessibility while running, re-granting it, and quitting all behaved as expected (Ando's checklist steps 13–16).

### Still open

- Volume down while muted at the bottom of the range (1/16 → 0) was not exercised, with stock macOS or ModernMac. ModernMac currently unmutes and lands on 0, which shows the muted icon anyway.
