# BRIEF — Phase 3: Preferences, persistence, polish

**Goal:** every parameter is tunable live, settings persist, the app feels finished and is cheap when idle.

**Read first:** `PRD.md` §5–6, `ARCHITECTURE.md` §1, §6. **Prereq:** Phase 2 accepted.

## Steps

### 3.1 Preferences window (SwiftUI)
- Opened from the menu (*Preferences…*, ⌘,). Hosted in a standard `NSWindow` via `NSHostingController`, with `level = .screenSaver + 1` while open so it is never covered or tilted by the effect.
- One labelled slider per parameter in `PRD.md` §5, each with a live numeric readout and the unit. Enum pickers for `easeCurve` and a segmented control for `leanDirection`.
- Constraint handling: `fullStrengthAngle` is always < `activationAngle` (clamp the other when one crosses).
- Buttons: **Reset to defaults**, and **Preview** (starts the simulator at the activation angle so the user can drag it while tuning).
- Changes apply instantly (the model re-evaluates on every parameter change) and persist.

### 3.2 Menu bar polish
- Optional live angle text (`showAngleInMenuBar`), `monospacedDigit` so the width doesn't jitter.
- Template image icon that works in light and dark menu bars. Make a simple original icon (e.g. an SF-Symbol-based hinge/laptop glyph) and an app icon of our own. Do not reuse anyone's artwork or the name "Duo".
- Status messages in the menu when something is wrong: *No lid angle sensor found*, *Screen Recording not granted*.

### 3.3 Robustness
- Settings migration: if a stored struct fails to decode, fall back to defaults instead of crashing.
- Sensor disconnect/failure: retry quietly with back-off; never spin.
- Ensure quitting while the overlay is visible always tears down the window and stops capture (the screen must never be left dimmed).
- Safety valve: if the app is stuck in the active zone with no sensor updates for >2 s, fade the overlay out.

### 3.4 Power and performance audit
- Activity Monitor / `powermetrics`: idle (lid open) CPU ≈ 0%, no capture session. Active effect: record CPU/GPU.
- Make sure timers, display link and SCStream are all stopped when disabled.

### 3.5 Docs
- `README.md`: what it is, requirements (Apple-silicon MacBook with a lid sensor, macOS 14+), build steps (`xcodegen generate`, `xcodebuild`), how to grant Screen Recording, how to use the simulator, known limitations (clicks not transformed, protected video, single built-in display).
- Update `DECISIONS.md` with the final parameter defaults after Maxwell's tuning.

## Acceptance checklist
- [ ] All parameters adjustable in Preferences with live effect updates.
- [ ] Settings survive quit/relaunch; corrupt settings don't crash.
- [ ] The screen is never left dimmed after quit, crash-recovery relaunch, or sensor loss.
- [ ] Idle CPU ≈ 0% and no capture session with the lid open.
- [ ] Menu shows clear status for missing sensor / missing permission.
- [ ] Own name, icon and artwork; no trace of the original product's branding.
- [ ] README written and accurate.
- [ ] Committed: `phase 3: prefs + polish`.

## Nice-to-haves (only if time remains; each needs Maxwell's OK)
Presets (Subtle / Default / Dramatic), a "calibrate: set activation to current lid angle" button, a hinge-angle history sparkline in the simulator panel.

## Final report format
**Done** · **Needs Maxwell** · **Surprises**.
