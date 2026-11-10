# ModernMac — Prompts for Claude Code

One prompt per phase, to paste into Claude Code in VS Code. They are short on purpose: the detail lives in `docs/SPEC.md` and `CLAUDE.md`, which Claude Code reads from the repo, so the prompts only say what this session is for, what "done" means, and where to stop.

## Before the first prompt

1. Create an empty folder `ModernMac`, open it in VS Code, and copy in `CLAUDE.md`, `docs/SPEC.md` and `docs/PROMPTS.md` keeping the same paths.
2. Make sure full Xcode is installed and has been opened once (licence accepted). Homebrew is needed for XcodeGen.
3. Create `docs/reference/` and drop in two or three screenshots or short screen recordings of the real macOS 26 volume and brightness HUD (light and dark if possible), plus anything from MediaMate you want the notch style to resemble. Claude Code can read images; this is the single biggest lever on visual fidelity, because the sizes in the spec are starting values.
4. Work one phase per session. Start each phase in plan mode, read the plan, then let it run. Start a fresh session (`/clear`) between phases; the repo, the spec and `docs/FINDINGS.md` carry the context.
5. After each phase, do the manual checklist Claude Code gives you and tell it the result before moving on.

---

## Phase 0 — Environment and feasibility

```text
We are starting ModernMac. Read CLAUDE.md and docs/SPEC.md fully before doing anything.

This session is Phase 0 from SPEC §8: prove the approach works on this Mac before we build on it. Nothing from this phase needs to be pretty.

Part A — environment. Check and report: macOS version (sw_vers), Xcode version and selected path, Swift version, whether xcodegen is installed, available code-signing identities (security find-identity -v -p codesigning), and the attached displays. If this Mac runs macOS 26 or later, or Xcode is missing, stop and tell me. If xcodegen is missing, ask before installing it with Homebrew.

Part B — scaffold. git init, a .gitignore (ModernMac.xcodeproj, .build/, Config/Local.xcconfig, .DS_Store), project.yml, the Makefile with every command in SPEC §7, Config/Local.xcconfig.example, docs/FINDINGS.md, and the smallest possible agent app: LSUIElement, a MenuBarExtra with the app name and Quit. Create the folder layout from SPEC §3 only as far as files exist to put in it. For signing, show me the identities you found and ask which to use; if there is none, walk me through creating a self-signed code-signing certificate and wait. `make build` and `make run` must work before Part C.

Part C — spike. Under Sources/Debug/Spike, behind #if DEBUG, add menu items to the menu bar extra that let me run each experiment by hand:
  1. "Tap: log only" — install the event tap in listen mode and log every system-defined event (type, subtype, decoded key code, down/up, repeat, modifier flags), plus plain keyDown events with key codes 144/145. Answers V1.
  2. "Tap: consume and handle" — active tap that consumes volume, mute and brightness keys and applies ±1/16 through CoreAudio and DisplayServices, logging old and new values. Answers V2, V3, V7.
  3. "Show blur test panel" — a borderless transparent non-activating panel with an NSVisualEffectView capsule (behind-window) next to a SwiftUI Material capsule. Answers V5.
  4. "Show notch-level test strip" — a red 200×(safe-area-top) strip at the top centre of the built-in screen at level mainMenu+3, and log the computed notch width and height. Answers V6.
  5. "Play feedback sound" — locate and play the stock volume feedback sound; log the path and the value of com.apple.sound.beep.feedback. Answers V4.
Request Accessibility permission when experiment 1 or 2 is first chosen.

Then stop and give me a numbered checklist: what to click, which keys to press, and what to tell you. Include two observations of stock macOS with our tap off: when the feedback sound plays (V8), and what volume up and volume down do while muted (V9). When I report back, write the results for V1–V9 into docs/FINDINGS.md with the exact values observed, update SPEC.md wherever reality differs, and commit.

If V2 fails (macOS still changes the level or shows its HUD while we consume the keys), do not start on a workaround: stop and explain what you saw.
```

## Phase 1 — Engine

```text
Read CLAUDE.md, docs/SPEC.md §3–§5.1 and docs/FINDINGS.md.

This session is Phase 1: the takeover engine, with no real HUD design yet.

Build, per the spec: MediaKey (decoding from data1), StepMath, KeyRouter (the full routing table in §4.2, as pure logic returning an action plus consume/pass-through), MediaKeyTap (all five tap requirements in §4.1), AudioController (§4.3, including property listeners, device name and icon selection, feedback sound with the timing recorded in FINDINGS), DisplayServicesBridge and BrightnessController (§4.4), PermissionManager (§4.5), HUDState and HUDCoordinator with an injected clock (§5.1). Put hardware behind VolumeControlling and BrightnessControlling and write fakes.

For now the HUD is a placeholder: a plain non-activating panel that prints kind, level and muted as text. Its only job is to show the coordinator is driven correctly.

Delete Sources/Debug/Spike once the real types replace it.

Unit tests (must pass with `make test`): every row of the routing table including modifier combinations and pass-through cases; grid snapping at the edges (0, 1, a level that sits between grid points, fine steps); media key decoding for down, up and repeat; fail-open cases (no settable volume, brightness unavailable, feature toggled off, handler returns an error → event passes through); coordinator timing (hide after delay, timer restarts on a new event, kind swap while visible, hover and drag hold it open).

Done means: tests green, `make run` works, and you hand me a checklist that walks every row of the routing table on the real keyboard, plus: quit the app and confirm the stock HUD returns immediately; revoke Accessibility while running and confirm keys keep working through macOS. Commit after I confirm.
```

## Phase 2 — HUD infrastructure and the macOS 26 style

```text
Read CLAUDE.md, docs/SPEC.md §5 and §7, docs/FINDINGS.md, and look at every image in docs/reference/.

This session is Phase 2: the real HUD window and the `tahoe` style.

Build: HUDPanel with the behaviour requirements in §5.2; HUDRootView that switches on the selected style; GlassBackground with live and snapshot rendering modes (§5.3, using whichever blur approach FINDINGS says works); LevelBar and HUDIcon as shared components; TahoeHUDView per the table in §5.4; the interactive slider per §5.5; the DEBUG simulate URL and snapshot mode per §7. Replace the placeholder panel.

Work visually in a loop: implement, `make snapshots`, read the PNGs, compare with docs/reference/, adjust the constants at the top of TahoeHUDView, repeat until you would be comfortable showing it. Then tell me which spec numbers you changed and why, and update the table in SPEC §5.4.

Unit tests: level-from-pointer-position mapping for the bar, drag throttling, panel frame calculation for each position setting on a fake screen (including a screen with a menu bar and one without).

Done means: tests green, snapshots for tahoe in light and dark at every level look right to you, and you give me a checklist covering: appears top-right under the menu bar on the right screen; never steals focus (type in a text editor while pressing volume keys); visible over a full-screen app and on a second Space; hover holds it open; drag changes the level smoothly; a click just outside the capsule reaches the app below; Reduce Motion and Increase Contrast behave per §5.4. Commit after I confirm.
```

## Phase 3 — Notch style

```text
Read CLAUDE.md, docs/SPEC.md §5.4 (notch table) and §5.2, docs/FINDINGS.md (notch dimensions and window level), and the images in docs/reference/.

This session is Phase 3: the `notch` style.

Build ScreenGeometry (notch rectangle from NSScreen safe-area and auxiliary areas, never hard-coded; nil on screens without a notch) and NotchHUDView with the collapsed and expanded states, wing content, animations, and the floating-pill fallback for screens without a notch. Use the window level proven in Phase 0. Order the panel out when collapsed and idle so nothing sits over the menu bar. Build the hover drawer with the draggable bar last, once the basic expand/collapse is right.

Add notch and pill cases to snapshot mode (draw a mock notch and menu bar in the backdrop so alignment is visible in the PNG), and iterate on the snapshots before asking me.

Unit tests: notch geometry from fake screen metrics (a notched 14-inch layout, a notched 16-inch layout, an external display), expanded frame calculation, fallback selection.

Done means: tests green, and a checklist for me covering: wings line up with the physical notch with no visible seam or gap; expansion and collapse feel like one shape, not a window appearing; menu bar items beside the notch are clickable again as soon as it collapses; with an external display as the main screen the pill appears there; the hover drawer opens and drags correctly. Commit after I confirm.
```

## Phase 4 — Circular style

```text
Read CLAUDE.md, docs/SPEC.md §5.4 (circular table) and §5.5, and the images in docs/reference/.

This session is Phase 4: the `circular` style.

Build CircularHUDView: glass disc, progress ring, centred symbol, optional percentage, appear and disappear animations, hover scale, and interaction by vertical drag and by scroll. Reuse GlassBackground and HUDIcon; share positioning with tahoe. Add it to snapshot mode and iterate on the PNGs first.

Unit tests: ring trim for edge levels, drag-distance-to-level mapping and clamping, scroll mapping.

Done means: tests green, and a checklist for me covering: the ring keeps up when a key is held; muted state is clear at a glance; drag and scroll change the level in the expected direction; it looks right in light and dark over a busy wallpaper. Commit after I confirm.
```

## Phase 5 — App shell

```text
Read CLAUDE.md and docs/SPEC.md §6.

This session is Phase 5: everything around the HUD.

Build AppSettings (@Observable, backed by UserDefaults, every key in the §6 table, applied live without relaunch); the Settings window with sections General (enabled, launch at login via SMAppService, menu bar icon), Appearance (style picker with the live preview described in §6, position, percentage, device name), Behaviour (hide delay, interactive, feedback sound, per-key toggles for volume and brightness), and About; the menu bar menu; the onboarding window with live permission status. Make sure Settings and onboarding come to the front when opened from an agent app.

Handle the case where the menu bar icon is hidden: launching the app again while it is running must open Settings, so the user is never locked out.

Unit tests: settings defaults and persistence round-trip using an isolated UserDefaults suite; disabling volume or brightness handling makes KeyRouter pass those keys through.

Done means: tests green, and a checklist for me that starts from a clean slate (tccutil reset, delete the app's defaults): first launch shows onboarding; granting permission flips the status without a relaunch; each setting takes effect immediately; launch at login survives a logout; hiding the menu bar icon and relaunching opens Settings. Commit after I confirm.
```

## Phase 6 — Hardening and release

```text
Read CLAUDE.md, docs/SPEC.md §9 and §10, and docs/FINDINGS.md.

This session is Phase 6: make it dependable, then package it.

First review the code against the "Rules that matter here" in CLAUDE.md and list any violations before fixing them. Then go through the test matrix in SPEC §9: for each item, say whether it can be covered by a unit test, by the simulate URL, or only by me, and handle them in that order. Add handling for screen-parameter changes, wake from sleep, default-device changes mid-display and permission loss wherever it is missing. Check idle cost: with the HUD hidden the app should do no periodic work beyond the tap health check and the permission poll, and there should be no leaked panels or listeners after 200 simulated show/hide cycles.

Then: write README.md (what it is, install, the permission and why, the three styles, known limits from SPEC §1 non-goals, how to build), add `make release` producing a signed Release build zipped in .build/release/, and add scripts/notarize.sh that documents the notarytool steps but only runs if the needed credentials are present.

Done means: tests green, a table in docs/FINDINGS.md with the result of every matrix item, and a final checklist of the items only I can run. Commit after I confirm.
```

---

## Reusable prompts

**Visual tuning** (any time after Phase 2):

```text
The <style> HUD does not match the reference yet. Compare .build/snapshots/ with docs/reference/<file> and with what I describe here: <what looks off — size, corner radius, blur strength, bar thickness, spacing, animation speed>. Change only the constants at the top of <Style>HUDView.swift and GlassBackground.swift, re-run `make snapshots`, and show me before/after values in a small table. Update SPEC §5.4 to the final numbers.
```

**Bug report:**

```text
Bug: <what I did> → <what happened> → <what I expected>. macOS <version>, style <style>, <any detail: device, display setup>.
Reproduce it first if you can (simulate URL, a failing unit test, or `make logs` while I repeat it). State the root cause before changing code, fix it at the cause, and add a test that would have caught it. If it contradicts the spec, tell me which one should change.
```

**Scope change:**

```text
I want to add <feature>. Before writing code: read docs/SPEC.md, tell me which sections and phases it touches, what it risks (especially the fail-open rule and the tap callback), and propose the spec edit. Wait for my go-ahead, then update the spec first and implement second.
```
