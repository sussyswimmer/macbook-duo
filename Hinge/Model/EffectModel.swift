import Foundation

/// Everything the renderers need for one frame.
struct EffectState: Equatable {
    /// Linear progress 0…1 (0 = inactive).
    var p: Double
    /// Eased progress 0…1.
    var e: Double
    /// Signed rotation of the display plane about its bottom edge.
    var leanRadians: Double
    /// Perspective strength 0…1.
    var perspective: Double
    /// Blur radius (points) at the very top edge for the current `e`.
    var maxBlurPx: Double
    var blurGamma: Double
    /// RGB multiplier, 1 = untouched.
    var brightness: Double

    static let inactive = EffectState(p: 0, e: 0, leanRadians: 0, perspective: 0,
                                      maxBlurPx: 0, blurGamma: 1, brightness: 1)

    var isActive: Bool { p > 0 }

    /// Blur radius in points at vertical position `v` (0 = bottom/hinge, 1 = top).
    func blurAt(_ v: Double) -> Double {
        maxBlurPx * pow(min(max(v, 0), 1), blurGamma)
    }

    /// 1 − brightness.
    var dim: Double { 1 - brightness }
}

/// θ → effect. Pure (PRD §4, ARCHITECTURE §4).
enum EffectModel {
    static func progress(angle θ: Double, params: EffectParameters) -> Double {
        let span = params.activationAngle - params.fullStrengthAngle
        guard span > 0 else { return θ < params.activationAngle ? 1 : 0 }
        return ((params.activationAngle - θ) / span).clamped(to: 0...1)
    }

    static func evaluate(angle θ: Double, params: EffectParameters) -> EffectState {
        guard params.enabled else { return .inactive }
        let p = progress(angle: θ, params: params)
        guard p > 0 else { return .inactive }
        let e = params.easeCurve.apply(p)
        let direction: Double = params.leanDirection < 0 ? -1 : 1
        return EffectState(
            p: p,
            e: e,
            leanRadians: e * params.maxLeanDegrees * .pi / 180 * direction,
            perspective: params.perspective,
            maxBlurPx: e * params.maxBlur,
            blurGamma: params.blurGamma,
            brightness: 1 - e * params.maxDim
        )
    }
}

/// How fast to poll the sensor (ARCHITECTURE §3 "Adaptive polling", with an
/// extra middle tier: see DECISIONS.md, Phase 1).
enum PollingPolicy {
    static let idleHz = 4.0
    static let approachHz = 15.0
    static let activeHz = 60.0
    /// Above `activationAngle + watchMargin`: idle rate.
    static let watchMargin = 15.0
    /// Within `activationAngle + activeMargin` (or below): full rate.
    static let activeMargin = 5.0
    /// Extra degrees needed before dropping to a slower tier, so a lid resting
    /// on a boundary doesn't flip rates on every 1° sensor tick.
    static let hysteresis = 3.0

    /// `angle` nil means "unknown yet": poll slowly until we know.
    /// `current` is the rate in use now (for hysteresis).
    static func rate(angle: Double?, params: EffectParameters, current: Double = 0) -> Double {
        guard params.enabled else {
            // Keep a slow poll only so the optional menu bar readout stays live.
            return params.showAngleInMenuBar ? idleHz : 0
        }
        guard let angle else { return idleHz }
        func tier(_ a: Double) -> Double {
            if a <= params.activationAngle + activeMargin { return activeHz }
            if a <= params.activationAngle + watchMargin { return approachHz }
            return idleHz
        }
        let target = tier(angle)
        // Speeding up is immediate; slowing down needs the extra margin.
        return target < current ? tier(angle - hysteresis) : target
    }
}
