# BRIEF — Phase 0: Environment + sensor proof

**Goal:** prove we can read the real lid angle from this Mac, resolve the raw unit, and have a buildable menu-bar skeleton. Nothing visual yet.

**Read first:** `CLAUDE.md`, `PRD.md`, `ARCHITECTURE.md` §3.

## Steps

### 0.1 Environment check (report results, don't assume)
- `sw_vers`, `xcodebuild -version`, `swift --version`, `system_profiler SPHardwareDataType | grep -E "Model|Chip"`.
- `which xcodegen` (if missing: `brew install xcodegen`).
- `security find-identity -v -p codesigning`. We need an *Apple Development* identity. If none exists, tell Maxwell to open Xcode → Settings → Accounts → add his Apple ID → create the Personal Team certificate, and list this under **Needs Maxwell**. Don't fall back to ad-hoc signing silently.
- Sensor presence: `hidutil list --matching '{"PrimaryUsagePage":32,"PrimaryUsage":138}'` (0x20 = 32, 0x8A = 138). Record the output verbatim in `DECISIONS.md`.

### 0.2 Project skeleton
- Create `~/code/hinge`, `git init`, `.gitignore` (Xcode, DerivedData, `.DS_Store`).
- `project.yml` for XcodeGen: macOS app target `Hinge`, deployment target 14.0, bundle ID `com.maxwell.hinge`, sandbox off, `LSUIElement` YES, test target `HingeTests`, signing with the Apple Development identity found above.
- `AppDelegate` with an `NSStatusItem` showing a placeholder SF Symbol and a menu containing only **Quit**.
- Build and launch from the command line with `xcodebuild`; confirm the icon appears in the menu bar and there is no Dock icon.

### 0.3 `LidSensor` + `AngleSource`
- Implement `AngleSource` and `LidSensor` exactly as in `ARCHITECTURE.md` §3 (IOHIDManager matching, feature report ID 1, poll via timer).
- Temporary debug output: show the **raw 16-bit value and the decoded angle** in the menu bar title, and log to `os.Logger`.
- Expose `rawToDegrees` as a single constant, initially `1.0`.

### 0.4 Resolve the unit (needs Maxwell for the physical part)
- Ask Maxwell to hold the lid at: **closed (just barely open)**, **~90° (a right angle)**, **fully open**. Capture the raw values at each.
- Decide: if closed ≈ 0 and 90° ≈ 90 → degrees. If 90° ≈ 9000 → 0.01° units. Set `rawToDegrees` and write the evidence in `DECISIONS.md`.
- If you cannot get physical readings in this session, make the menu bar show both interpretations (`raw` and `raw/100`) and leave the check to Maxwell under **Needs Maxwell**.

### 0.5 `AngleProcessor` + tests
- Implement deadband + smoothing as a pure struct (`ARCHITECTURE.md` §3).
- XCTest cases: constant input stays constant; a step input converges within ~3× `smoothingMs`; jitter under the deadband produces no output change; result is frame-rate independent (same result at 30 / 60 / 120 Hz stepping).

## Acceptance checklist
- [ ] App builds with `xcodebuild`, signed with a stable Apple Development identity.
- [ ] Menu-bar item appears; no Dock icon; Quit works.
- [ ] Menu bar shows a live angle that tracks the physical lid (or Maxwell's confirmation is listed under Needs Maxwell).
- [ ] The raw unit is resolved and documented, or both candidates are displayed.
- [ ] `AngleProcessor` tests pass.
- [ ] If no sensor is found, the app says so clearly rather than crashing.
- [ ] `DECISIONS.md` created with the environment results, sensor output and unit decision.
- [ ] Committed: `phase 0: sensor proof`.

## Final report format
Three parts: **Done** (≤5 bullets), **Needs Maxwell** (physical checks, certificate), **Surprises** (anything that contradicts the docs).
