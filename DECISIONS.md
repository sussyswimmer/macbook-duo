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

If the unit were 0.01°, 122 would mean 1.2° — the lid would be shut while Maxwell was
using the screen. So the value is whole degrees, with 1° resolution. Still worth a
3-point physical check (closed / 90° / fully open) — listed under *Needs Maxwell*.

Consequence of 1° resolution: the 0.3° deadband only filters sensor noise between
neighbouring integers; the spring smoothing is what turns 1° steps into smooth motion.

### Smoothing
Critically-damped spring, integrated with its exact closed-form solution (so it's
frame-rate independent). `ω = 4 / smoothingMs`: a step is ~91% done after `smoothingMs`
and fully settled by 3×. No overshoot.
