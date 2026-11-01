# ARCHITECTURE — Hinge

## 1. Component overview

```
                 ┌──────────────────────┐
  hardware ───►  │ LidSensor (IOKit HID)│──┐
                 └──────────────────────┘  │  AngleSource protocol
                 ┌──────────────────────┐  ├──────────────────────┐
  slider   ───►  │ SimulatedAngleSource │──┘                      ▼
                 └──────────────────────┘             ┌─────────────────────┐
                                                      │ AngleProcessor      │ deadband + smoothing
                                                      └──────────┬──────────┘
                                                                 ▼
 EffectParameters ───────────────────────────────►  ┌─────────────────────┐
 (UserDefaults)                                     │ EffectModel         │ θ → p → lean, blur, dim
                                                    └──────────┬──────────┘
                                                               ▼
                           ┌───────────────────────────────────────────────────────┐
                           │ OverlayController (built-in display only)             │
                           │  Phase 1: NSVisualEffectView blur + black dim layer   │
                           │  Phase 2: ScreenCaptureKit → Metal quad renderer      │
                           └───────────────────────────────────────────────────────┘
 MenuBarController · PreferencesView (SwiftUI) · SimulatorPanel
```

## 2. Suggested file layout

```
hinge/
  project.yml                 # XcodeGen
  Hinge/
    App/            HingeApp.swift, AppDelegate.swift, MenuBarController.swift
    Sensor/         AngleSource.swift, LidSensor.swift, SimulatedAngleSource.swift
    Model/          EffectParameters.swift, AngleProcessor.swift, EffectModel.swift
    Overlay/        OverlayWindow.swift, OverlayController.swift, DisplayLocator.swift
    Render/         (Phase 2) ScreenCapturer.swift, EffectRenderer.swift, Shaders.metal
    UI/             PreferencesView.swift, SimulatorPanel.swift
    Resources/      Info.plist, Hinge.entitlements, Assets.xcassets
  HingeTests/       AngleProcessorTests, EffectModelTests, MatrixTests
  DECISIONS.md
```

## 3. Sensor layer

**Protocol**
```swift
protocol AngleSource: AnyObject {
    var onAngle: ((Double) -> Void)? { get set }   // degrees, 0 = closed
    func start(rateHz: Double)
    func stop()
}
```

**LidSensor (real hardware)**
- `IOHIDManagerCreate`; matching dict: `VendorID=0x05AC`, `ProductID=0x8104`, `PrimaryUsagePage=0x20`, `PrimaryUsage=0x8A`.
- Open the manager, take the first matching `IOHIDDevice`, `IOHIDDeviceOpen`.
- Read with `IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &buf, &len)` into a small buffer (3+ bytes). It is a **synchronous poll**, so drive it from a `DispatchSourceTimer` on a utility queue, then hop to main for UI.
- Decode `raw = UInt16(buf[1]) | UInt16(buf[2]) << 8`. Phase 0 settles `degrees = raw` vs `raw / 100`; encode the answer as one constant `rawToDegrees`.
- If no device matches, publish a clear error state ("No lid angle sensor found") and let the simulator remain usable.
- If `IOHIDDeviceOpen` returns a permission error, check whether macOS wants *Input Monitoring* for this binary and document it in `DECISIONS.md`.

**Adaptive polling (power)**
| Condition | Rate |
|---|---|
| `θ > activationAngle + 15°` | 4 Hz (just watching for the lid to come down) |
| within the active zone, or ±15° of activation | 60 Hz |
| effect disabled | stopped |

**AngleProcessor**
1. Deadband: ignore changes < ~0.3° (sensor jitter).
2. Smoothing: critically-damped spring (or one-pole low-pass) with a time constant `smoothingMs`. Frame-rate independent (use `dt`).
3. Pure function plus a small state struct, so it is trivially unit-testable.

## 4. Effect model (pure math, fully unit-tested)

```
p = clamp((activation − θ) / (activation − fullStrength), 0, 1)
e = ease(p)                         // linear | smoothstep | easeOut
leanRadians = e · maxLeanDegrees · π/180 · leanDirection
blurAt(v)  = e · maxBlur · v^blurGamma        // v: 0 bottom … 1 top
brightness = 1 − e · maxDim
```
`EffectModel.evaluate(θ, params) -> EffectState { p, e, leanRadians, perspective, maxBlurPx, blurGamma, brightness }`.

## 5. Rendering

### 5a. Overlay window (both phases)
- Borderless `NSWindow` subclass: `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `ignoresMouseEvents = true`, `level = .screenSaver`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`.
- Frame = the **built-in** display's frame. Find it with `CGDisplayIsBuiltin(displayID)` via `NSScreen.deviceDescription["NSScreenNumber"]`. Re-evaluate on `NSApplication.didChangeScreenParametersNotification` (external display attach, clamshell).
- Show only while `p > 0`. Hide when `p == 0`.
- The Simulator panel and the Preferences window must sit **above** the overlay (`level = .screenSaver + 1`) and be excluded from capture.

### 5b. Phase 1 — no capture permission
- Overlay content view = `NSVisualEffectView` (`blendingMode = .behindWindow`, `state = .active`, a dark/hud material) with a `CAGradientLayer` mask whose coverage grows from the top edge, plus a black `CALayer` whose opacity = `e · maxDim`.
- Limitations: blur radius is fixed by the material (only coverage/opacity varies); there is no 3D lean. That's expected. This phase proves the sensor→effect pipeline and the window behavior.
- If behind-window blur does not blur other apps' windows in this configuration, note it and go straight to Phase 2.

### 5c. Phase 2 — capture + Metal
**Capture (`ScreenCapturer`)**
- `SCShareableContent` → find the built-in `SCDisplay`.
- `SCContentFilter(display:excludingApplications:[ownApp] exceptingWindows:[])` so our own overlay, panel and prefs are **never captured** (otherwise: feedback loop).
- `SCStreamConfiguration`: native pixel size, `pixelFormat = kCVPixelFormatType_32BGRA`, `showsCursor = false` (the real cursor still draws above the overlay), `queueDepth = 3`, `minimumFrameInterval = 1/60`, color space set explicitly to the display's color space to avoid a hue/gamma jump at handoff.
- Frames arrive as `CMSampleBuffer` → `IOSurface` → `MTLTexture` (zero-copy via `CVMetalTextureCache` or `device.makeTexture(descriptor:iosurface:plane:)`). Keep only the latest frame; drop older ones.
- **Warm-up/shutdown:** start the stream when `θ < activationAngle + 10°`, stop it when `θ > activationAngle + 15°` (hysteresis). That avoids first-frame latency at activation and avoids capturing when idle.

**Renderer (`EffectRenderer`, `MTKView` or `CAMetalLayer` in the overlay window)**
1. Per frame, build a mip chain of the latest captured texture (`MTLBlitCommandEncoder.generateMipmaps`).
2. Draw one quad for the display plane. Vertex stage: model matrix rotates about the **bottom edge** (X axis at y = 0) by `leanRadians`; view/projection gives perspective of strength `perspective`. Calibrate so `leanRadians = 0` maps the quad *exactly* onto the viewport. Use perspective-correct texture coordinates (interpolate `uv/w`, which the GPU does for you).
3. Fragment stage: `v` = texture-space vertical coordinate (0 bottom … 1 top). Compute `lod = (blurAt(v) / maxBlur) · maxLod` and sample with `texture.sample(trilinearSampler, uv, level(lod))`. Multiply RGB by `brightness`.
4. Clear color is opaque black. While tilting, the area the plane vacates must show black, not the live desktop (the overlay must fully hide the real screen).
5. Upgrade path if mip-LOD blur looks blocky: dual-Kawase down/up passes at 2–3 levels, blended by the same per-pixel factor. Do this only if the visual quality demands it.

**Driving frames:** `CADisplayLink` from the view (`NSView.displayLink(target:selector:)`, macOS 14+) so it matches the display's refresh (60/120 Hz). Render on the display-link callback using the latest `EffectState` and the latest frame. Never block the main thread on capture.

## 6. Permissions & signing
- Phase 1 needs none beyond possibly Input Monitoring for the HID device (verify).
- Phase 2 needs **Screen Recording**. macOS prompts the first time `SCStream` starts. A relaunch is often required after granting.
- Signing: Apple Development certificate (Personal Team) so the TCC grant survives rebuilds. Ad-hoc signing makes macOS forget the permission each build.
- `Info.plist`: `LSUIElement = YES`, `NSScreenCaptureUsageDescription` (short honest text), `LSMinimumSystemVersion = 14.0`.
- Entitlements: sandbox **off**. Hardened runtime on is fine for local use.

## 7. Threading
| Work | Thread/queue |
|---|---|
| Sensor poll | utility `DispatchSourceTimer` |
| Angle → `EffectState` | main (cheap) |
| SCStream callbacks | dedicated serial queue; hand over latest texture atomically |
| Metal encode/commit | main, from the display-link callback |

## 8. Known risks
| Risk | Mitigation |
|---|---|
| Raw unit differs from assumption | Phase 0 logging at three known angles |
| Reverse-engineered sensor path changes with a macOS update | Isolate in `LidSensor`; the simulator keeps everything else testable |
| Capture lag makes the handoff visible | Warm-up margin, same color space, pixel-identical identity transform, test at slow and fast closing speeds |
| Screen Recording grant lost on rebuild | Stable signing identity |
| Protected video blank, HDR tone-mapped to SDR | Accepted |
| Click targets don't follow the tilted image | Accepted |
| High GPU/battery use on 120 Hz | Idle shutdown; optionally capture at half resolution when blur is large |
