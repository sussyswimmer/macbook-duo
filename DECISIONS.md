# DECISIONS — Hinge

Running log of environment facts, empirical answers and judgement calls.

## Phase 0 — environment + sensor (2026-11-01)

### Environment
| Check | Result |
|---|---|
| `sw_vers` | macOS 26.5.2 (25F84) |
| `xcodebuild -version` | Xcode 26.4 (17E192) — **but** `xcode-select` points at CommandLineTools |
| `swift --version` | Apple Swift 6.1.2 (CLT); Xcode toolchain used for builds |
| Hardware | MacBook Pro, Mac15,3, Apple M3 |
| `xcodegen` | not installed → `brew install xcodegen` → 2.46.0 |
| Signing identity | `Apple Development: maxwell.olander@gmail.com (WMD3RWQAC7)`, team `6W76XB4K67` (OU of the cert) |

**Decision:** don't `sudo xcode-select -s`; the `Makefile` exports
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` instead. Maxwell can run
`sudo xcode-select -s /Applications/Xcode.app` himself if he wants plain `xcodebuild` to work.

**Decision:** manual signing with `CODE_SIGN_IDENTITY = "Apple Development"` + team
`6W76XB4K67`, hardened runtime on, sandbox off. Verified with `codesign -dv`:
`Authority=Apple Development: …`, `TeamIdentifier=6W76XB4K67`. No provisioning profile is
needed (no restricted entitlements).

**Decision:** Swift language mode 5 (compiled by the Swift 6 toolchain) to avoid strict
concurrency churn on AppKit/IOKit callbacks. Revisit if it ever matters.

**Decision:** the test bundle has no host app; pure-logic sources (`Hinge/Model`) are compiled
directly into `HingeTests`, so running tests never launches the menu-bar app.

### Sensor presence
`hidutil list --matching '{"PrimaryUsagePage":32,"PrimaryUsage":138}'`, verbatim:

```
Services:
VendorID ProductID LocationID UsagePage Usage RegistryID  Transport Class             Product UserClass Built-In 
0x5ac    0x8104    0x0        32        138   0x10000092c SPU       AppleSPUHIDDriver (null)  (null)    1        

Devices:
VendorID ProductID LocationID UsagePage Usage RegistryID  Transport Class             Product UserClass Built-In 
0x5ac    0x8104    0x0        32        138   0x1000008d8 SPU       AppleSPUHIDDevice (null)  (null)    1        
```

### Permissions
`IOHIDManagerOpen` and `IOHIDDeviceOpen` both return `kIOReturnSuccess` from the signed
`Hinge.app` and from an unsigned CLI probe. **No Input Monitoring prompt** — the sensor hub
orientation device is not gated by TCC on macOS 26.5.

### Raw unit → **whole degrees** (`rawToDegrees = 1.0`)
Feature report 1 returns 3 bytes `[01, lo, hi]`. Evidence:

| Lid position | Bytes | Raw |
|---|---|---|
| normal working angle (screen in use) | `01 7a 00` | 122 |
| moments later, lid pushed further down (still in use) | `01 60 00` | 96 |

| lid fully open (Phase 1 recorded session) | — | 131 |

If the unit were 0.01°, 122 would mean 1.2° — the lid would be shut while Maxwell was
using the screen — and 131 at fully open matches a MacBook Pro's ~130–135° maximum. So
the value is whole degrees, with 1° resolution. Still missing: a reading at ~90° and
just-closed (listed under *Needs Maxwell*).

Consequence of 1° resolution: the 0.3° deadband only filters sensor noise between
neighbouring integers; the spring smoothing is what turns 1° steps into smooth motion.

### Smoothing
Critically-damped spring, integrated with its exact closed-form solution (so it's
frame-rate independent). `ω = 4 / smoothingMs`: a step is ~91% done after `smoothingMs`
and fully settled by 3×. No overshoot.

## Phase 1 — overlay + blur/dim (2026-11-01)

### Q2: does behind-window `NSVisualEffectView` blur other apps' windows? → **yes, but unusable here**
- First attempt (full-screen `NSVisualEffectView`, `.hudWindow`, gradient `maskImage`, black
  dim layer): Maxwell saw **only dimming/tint, no blur**, and the motion was **jittery**.
- Probe A (plain `NSVisualEffectView`, `.fullScreenUI`, no mask, no dim, top half of the
  screen at `.screenSaver` level): **blurred**. So behind-window blur works from a
  borderless screen-saver-level window; the per-pixel-alpha mask is what broke it (partial
  alpha just cross-fades sharp content with a fixed blur and reads as a tint), and
  rebuilding `maskImage` every frame caused the jitter.
- The material's radius is fixed, so it can't express `blurAt(v)` anyway.

### Decision: Phase 1 blur uses the window-server background blur, in strips
- Probe B: `CGSSetWindowBackgroundBlurRadius(CGSMainConnectionID(), windowNumber, 24)` on a
  borderless window with a 1/255 black background → Maxwell: **"blurred, no tint"**.
- It is **private SPI** (the call terminal apps use for blurred backgrounds). Acceptable for
  a personal, never-distributed tool. Looked up via `dlsym`, so if a macOS update removes it
  the app degrades to dim-only instead of failing to launch (`WindowServerBlur.swift`).
- Graduated blur: the built-in display is covered by **24 horizontal strip windows**
  (`OverlayController.stripCount`), each blurring with radius `blurAt(v)` at its centre.
  Dim is a black layer at opacity `e·maxDim` in every strip (a Core Animation opacity change,
  no AppKit redraw). The radius is only re-sent when its rounded value changes.
- Maxwell's check with the simulator: **graduated blur visible, smooth, panel crisp, clicks
  pass through, clears fully above 105°.** No visible seams between strips were reported.
- Phase 2 still replaces this with the captured + Metal renderer (lean needs capture);
  this path stays as the fallback when Screen Recording isn't granted.

### Decision: animation is display-synced
`FrameClock` (a `CADisplayLink` from the built-in `NSScreen`) advances the spring and
re-renders every display frame while the spring is moving and the sensor is in a fast tier;
it pauses as soon as the spring settles. Samples and frames share one clock in `AngleHub`,
so time is never double-counted.

### Decision: adaptive polling gets a middle tier (deviation from ARCHITECTURE §3)
Measured cost of one `IOHIDDeviceGetReport`: ~0.9 ms wall, ~0.2–0.3 ms CPU. Polling at
60 Hz cost ~3% CPU, and Maxwell's normal working angle (113–122°) sits inside the
documented 60 Hz zone (≤ activation + 15° = 120°). New tiers:

| Smoothed/raw angle (lower of the two) | Rate |
|---|---|
| > activation + 15° | 4 Hz |
| activation + 5° … + 15° | 15 Hz |
| ≤ activation + 5° (incl. the active zone) | 60 Hz |
| disabled | stopped (4 Hz if "Show lid angle in menu bar" is on) |

Slowing down needs an extra 3° (hysteresis) so a lid resting on a boundary doesn't flip
rates every tick (observed before the fix: 4→60→4 Hz within 10 ms at 120°).
The display-synced spring hides the lower sample rate in the 15 Hz tier.
**Measured:** lid at 121° → 4 Hz, Hinge at **0.0–0.2% CPU**.

### Smaller decisions
- **Simulator panel:** opening it switches to the simulated source (slider at 120°, or
  `-debugSimAngle N`); closing it returns to the real sensor. The processor keeps its state
  across switches, so the effect glides rather than jumps. While the simulator is the source
  it is always serviced at 60 Hz.
- `isFloatingPanel = true` resets an `NSPanel`'s level to `.floating`, so it must be set
  before `level = .screenSaver + 1` (caught via the window list: the panel was at layer 3).
- **QA hook:** `open Hinge.app --args -debugSimAngle 60` launches straight into the
  simulator at that angle.
- `EffectParameters` decodes per key with fallback to defaults, so one bad or missing key
  never discards the rest.

### Physical lid test → **passes**
Maxwell confirmed "it works". Logs (15:23:50–15:24:11) show the real sensor showing and
hiding the overlay repeatedly, reaching `p = 1.000` and clearing every time, with polling
stepping 4 → 15 → 60 Hz.

### Fix: no pop-in after a slow-rate sample
The same logs showed the overlay appearing straight at `p = 1.000` after a 4 Hz sample: the
whole gap since the previous sample (≥250 ms ≈ 3τ) was spent moving toward the *new* angle,
so the spring finished in a single step. `AngleHub.ingest` now spends elapsed time on the
old target, then retargets, so the display clock animates the change from where it was.
