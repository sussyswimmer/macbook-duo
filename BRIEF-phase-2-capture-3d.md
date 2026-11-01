# BRIEF — Phase 2: ScreenCaptureKit + Metal 3D lean + graduated blur

**Goal:** the real effect. The built-in display is captured and re-rendered as a plane that leans away about the hinge, with blur that increases toward the far edge and a dim toward black, all at ≥60 fps and with an invisible handoff.

**Read first:** `ARCHITECTURE.md` §4–6 fully, `PRD.md` §4. **Prereq:** Phase 1 accepted.

## Steps

### 2.1 Permission + capture
- `ScreenCapturer` per `ARCHITECTURE.md` §5c: find the built-in `SCDisplay`; `SCContentFilter(display:excludingApplications:[ownApp] exceptingWindows:[])`; BGRA, native resolution, `showsCursor = false`, `queueDepth = 3`, `minimumFrameInterval = 1/60`, explicit color space.
- Handle the Screen Recording flow gracefully: if access is not granted, show a menu item *"Grant Screen Recording…"* that opens System Settings → Privacy & Security → Screen Recording, and fall back to the Phase 1 overlay in the meantime. Remind Maxwell that a relaunch is usually needed after granting.
- Frames → `IOSurface` → `MTLTexture` zero-copy. Keep only the newest frame.
- **Warm-up/shutdown hysteresis** from `ARCHITECTURE.md` §5c: start at `θ < activation + 10°`, stop at `θ > activation + 15°`.

### 2.2 Renderer
- Replace the Phase 1 content view with a Metal view (`MTKView` or `CAMetalLayer`) in the same overlay window; keep the Phase 1 path as a fallback toggled by capture availability.
- `Shaders.metal`: vertex stage (rotate about the bottom edge, perspective projection, calibrated so zero lean == exact viewport fill) and fragment stage (mip-LOD blur driven by `blurAt(v)`, brightness multiply).
- Per frame: `generateMipmaps` on the latest texture, draw the quad, present. Opaque black clear colour so vacated area is black.
- Drive with `CADisplayLink` (`NSView.displayLink(target:selector:)`).
- Expose a constant `leanDirection` (from parameters) and verify visually which sign makes the screen "lean away from the viewer", with the top edge receding.

### 2.3 Seamless handoff (the part that makes it feel real)
- At `p = 0` the rendered image must equal the real screen: same scale, position, colour. Test with a static, detailed wallpaper and a text-heavy window. Toggle the overlay on/off at `p ≈ 0` via the sim slider and look for any shift, flash, or colour change.
- Fix colour mismatch by aligning the capture colour space with the display's. Fix scale/position mismatch in the projection calibration, not with fudge factors.
- Verify behaviour at slow and fast lid movement; the warm-up margin should hide capture start latency.

### 2.4 Blur quality pass
- Evaluate the mip-LOD blur. If banding or blockiness is visible, implement dual-Kawase down/up at 2–3 levels and blend by the same per-pixel factor. Only add complexity if the quality needs it.

### 2.5 Performance
- Target ≥60 fps (≥ display refresh if cheap) on the built-in ProMotion display during the effect, and **0 capture/GPU work when idle**.
- Measure with Instruments (Metal System Trace) or the Xcode GPU HUD; record numbers in `DECISIONS.md`.
- If the cost is high, capture at half resolution while blur is large (blurred content doesn't need full-res).

### 2.6 Edge cases
- External display attached/detached; clamshell; sleep/wake (re-create the stream after wake); display resolution change; Spaces/full-screen apps (overlay must appear over full-screen spaces); the effect turning on while a full-screen video is playing (accept blank for protected video).

## Acceptance checklist
- [ ] Closing the lid / dragging the sim slider shows lean + far-edge-heavier blur + dim, reversible.
- [ ] No visible pop when the overlay appears/disappears at activation.
- [ ] Our own windows (overlay, simulator, prefs) are never captured, and there is no feedback loop.
- [ ] ≥60 fps during the effect; zero capture when the lid is comfortably open.
- [ ] Screen Recording denied → graceful fallback to Phase 1 effect plus a menu hint.
- [ ] Works across sleep/wake and display changes without a relaunch (or the limitation is documented).
- [ ] Math tests for the projection matrix pass (zero lean == identity fill; lean pivots about the bottom edge).
- [ ] `DECISIONS.md` has lean direction, blur method, perf numbers.
- [ ] Committed: `phase 2: capture + 3D lean`.

## Final report format
**Done** · **Needs Maxwell** (eyes-on quality check, granting permission, physical lid test) · **Surprises**.
