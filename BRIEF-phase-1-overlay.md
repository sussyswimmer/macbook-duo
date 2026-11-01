# BRIEF — Phase 1: Overlay + blur/dim (no capture permission)

**Goal:** closing the lid (or dragging a simulated angle slider) visibly blurs and dims the built-in display, reversibly. This validates the whole sensor → model → window pipeline before any ScreenCaptureKit complexity.

**Read first:** `CLAUDE.md`, `PRD.md` §4–6, `ARCHITECTURE.md` §3–5b. **Prereq:** Phase 0 accepted.

## Steps

### 1.1 `EffectParameters` + `EffectModel`
- `EffectParameters` with every key in `PRD.md` §5, defaults and ranges, `Codable`, persisted to `UserDefaults` (use one key holding the encoded struct).
- `EffectModel.evaluate(θ, params) -> EffectState`, pure.
- XCTest: `p = 0` at/above activation; `p = 1` at/below full-strength; monotonic in between; each easing curve maps 0→0 and 1→1; `brightness` and `blurAt(v)` formulas match the spec; swapping `leanDirection` flips only the lean sign.

### 1.2 `SimulatedAngleSource` + `SimulatorPanel`
- `SimulatedAngleSource` conforms to `AngleSource`.
- `SimulatorPanel`: a floating `NSPanel` (non-activating, `level = .screenSaver + 1`) with an angle slider 0–180° (default 120°), a live number, and a **Use real sensor** checkbox. Opens from the menu item *Simulate lid angle…*.
- Add `AngleHub`: owns the active source (real or simulated), applies `AngleProcessor`, publishes `θ` to the model and menu bar. Switching sources is instant and safe.

### 1.3 Overlay window
- `DisplayLocator`: finds the built-in `NSScreen` (CGDisplayIsBuiltin). Recompute on screen-parameter changes. If no built-in display is active (clamshell), the overlay is simply disabled.
- `OverlayWindow` and `OverlayController` as in `ARCHITECTURE.md` §5a. The overlay is shown only while `p > 0`, hidden otherwise.
- Content: `NSVisualEffectView` (behind-window, active) + gradient mask whose coverage grows from the **top** edge with `e`, plus a black layer at opacity `e · maxDim`.
- Make sure the overlay never receives mouse events and never steals focus.

### 1.4 Menu items
- **Enabled** toggle (checkmark) · **Show lid angle in menu bar** · **Simulate lid angle…** · **Quit**. Wire them to `EffectParameters`.

### 1.5 Adaptive polling
- Implement the table in `ARCHITECTURE.md` §3: 4 Hz when well open, 60 Hz near/in the active zone, stopped when disabled. Verify in Activity Monitor that idle CPU stays near 0%.

### 1.6 Answer the open question
- Does behind-window blur actually blur *other apps' windows* here? Record yes/no (and a one-line description of how it looks) in `DECISIONS.md`. If **no**, still finish the dim part and flag that Phase 2 is required for real blur.

## Acceptance checklist
- [ ] Dragging the sim slider from 120° to 0° smoothly increases blur/dim; dragging back reverses it with no stuck state.
- [ ] Above `activationAngle` there is no overlay window at all (verify: no visual change, near-zero CPU).
- [ ] Physical lid close/open drives the same effect (or listed under Needs Maxwell).
- [ ] Overlay never blocks clicks or takes focus.
- [ ] Simulator panel stays crisp, never blurred or dimmed.
- [ ] Disabling from the menu removes the overlay immediately.
- [ ] Unit tests for `EffectModel` pass.
- [ ] `DECISIONS.md` updated (behind-window blur result).
- [ ] Committed: `phase 1: overlay + blur/dim`.

## Final report format
**Done** · **Needs Maxwell** · **Surprises**.
