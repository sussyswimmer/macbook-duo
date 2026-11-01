# PRD — Hinge (personal lid-angle screen effect)

## 1. Summary
A menu-bar app for Maxwell's MacBook Pro (M3/M4/M5 family). When the lid closes below a threshold angle, the built-in display visibly leans away, blurs progressively from its far edge, and dims toward black, in step with the real hinge angle (not a canned animation). Opening the lid unwinds it identically in reverse. The app is invisible otherwise.

It replicates the behavior described on a commercial product page (a ~€6 Mac app): "leans away, blurs from the far edge, fades out in step with the real hinge angle", reading the sensor ~60×/s, all parameters adjustable. This is a clean-room personal rebuild.

## 2. Goals
1. Read the lid angle reliably from the hardware sensor at up to 60 Hz.
2. Render a smooth (≥60 fps) lean + graduated blur + dim on the built-in display, driven by that angle.
3. Menu-bar-only UX with a Preferences window to tune every parameter.
4. A **simulated-angle slider** so the whole effect can be developed and tested without moving the lid.
5. Near-zero idle cost: no polling/capture when the lid is comfortably open.

## 3. Non-goals (explicitly out of scope)
- Launch at login, global hotkey, auto-update, analytics, licensing, payments, App Store, notarization.
- External displays (effect applies to the built-in display only).
- Intel Macs and pre-2019 hardware.
- Transforming real click targets: only the *image* is transformed; clicks land on the untransformed UI. Accepted limitation.
- Protected/DRM video and HDR fidelity: may render blank or SDR. Accepted limitation.
- Controlling sleep behavior; macOS handles lid-close sleep itself.

## 4. Behavior spec
Let `θ` = smoothed lid angle in degrees (0 closed … ~180 open).

- **Inactive zone:** `θ ≥ activationAngle` → nothing drawn, overlay hidden, capture stopped.
- **Ramp:** progress `p = clamp((activationAngle − θ) / (activationAngle − fullStrengthAngle), 0, 1)`, then eased: `e = easeCurve(p)`.
- **Lean:** the display plane rotates about its bottom edge (the hinge axis) by `φ = e · maxLeanDegrees`, so the top edge recedes. Perspective projection with configurable strength. Direction is a constant (`leanDirection = ±1`) so it can be flipped if it looks wrong.
- **Blur:** radius increases toward the far (top) edge: `blur(v) = e · maxBlur · v^blurGamma`, where `v ∈ [0,1]` runs from the bottom edge (0) to the top (1).
- **Dim/fade:** brightness multiplier `1 − e · maxDim`. At full strength the screen is nearly black.
- **Seamless handoff:** at `p → 0` the rendered overlay must be pixel-identical in position, scale and color to the real screen, so there is no visible pop when the overlay appears or disappears.
- **Reversibility:** same mapping in both directions; there is no hysteresis state beyond sensor smoothing.
- **Response:** `θ` is passed through a smoothing filter (default critically-damped, ~80 ms response) after a small deadband, to remove sensor jitter without feeling laggy.

## 5. Parameters (single `EffectParameters` struct, persisted in `UserDefaults`)

| Key | Meaning | Default | Range |
|---|---|---|---|
| `enabled` | Master switch | true | — |
| `activationAngle` | Angle where the effect begins | 105° | 40–150° |
| `fullStrengthAngle` | Angle where effect reaches max | 25° | 0–90° (< activation) |
| `maxLeanDegrees` | Plane rotation at full strength | 50° | 0–80° |
| `perspective` | Camera FOV / depth strength | 0.6 | 0–1 |
| `maxBlur` | Max blur radius at far edge (points) | 28 | 0–80 |
| `blurGamma` | How concentrated blur is at the far edge | 1.6 | 0.5–3 |
| `maxDim` | Max darkening | 0.95 | 0–1 |
| `easeCurve` | Linear / smoothstep / ease-out | smoothstep | enum |
| `smoothingMs` | Sensor smoothing response time | 80 | 0–300 |
| `leanDirection` | Which way the plane tilts | +1 | ±1 |
| `showAngleInMenuBar` | Show the live angle as menu bar text | false | — |

## 6. UX
- **Menu bar item** (`NSStatusItem`): icon (or live angle text). Menu: *Enabled* toggle · *Show lid angle in menu bar* toggle · *Simulate lid angle…* · *Preferences…* · *Quit*.
- **Preferences window** (SwiftUI): a slider per parameter above with a live readout and *Reset to defaults*. Changes apply immediately.
- **Simulator panel:** a small floating panel with an angle slider (0–180°) and a "Use real sensor" toggle. The panel sits above the effect overlay so it is never blurred or tilted.
- No Dock icon, no windows on launch, no notifications.

## 7. Decisions already made (from Maxwell)
- Chip: M3/M4/M5 family. The sensor is expected to be present; Phase 0 confirms it.
- Build is **phased**: blur+dim first (no capture permission), then capture + 3D lean.
- Audience: just Maxwell. Run locally, no distribution.
- Included extras: simulated-angle slider, Preferences window. Excluded: launch at login, global hotkey.

## 8. Success criteria
- Phase 0: live angle printed from the real sensor with the unit resolved.
- Phase 1: closing the lid (or dragging the sim slider) visibly blurs and dims the built-in display, reversibly, with no Screen Recording permission.
- Phase 2: the full lean + graduated blur + dim runs at ≥60 fps; the handoff at activation is invisible; the capture and polling stop when idle.
- Phase 3: every parameter is tunable live; settings persist across relaunch; idle CPU ≈ 0%.

## 9. Open questions for the build to answer (record in `DECISIONS.md`)
1. Raw sensor unit (whole degrees vs 0.01°).
2. Does a behind-window `NSVisualEffectView` blur other apps' windows from a borderless screen-saver-level window? If not, skip straight to Phase 2.
3. Which lean direction looks right?
4. Does the 3D look need an extra downscale of the capture for speed on 120 Hz ProMotion?
