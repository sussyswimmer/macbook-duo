import Foundation

enum EaseCurve: String, Codable, CaseIterable, Identifiable {
    case linear
    case smoothstep
    case easeOut

    var id: String { rawValue }

    var label: String {
        switch self {
        case .linear: return "Linear"
        case .smoothstep: return "Smoothstep"
        case .easeOut: return "Ease out"
        }
    }

    /// Maps 0…1 → 0…1 with f(0) = 0 and f(1) = 1.
    func apply(_ x: Double) -> Double {
        let p = min(max(x, 0), 1)
        switch self {
        case .linear: return p
        case .smoothstep: return p * p * (3 - 2 * p)
        case .easeOut:
            let q = 1 - p
            return 1 - q * q * q
        }
    }
}

/// Every tunable number in the app (PRD §5). Persisted as one encoded blob.
struct EffectParameters: Codable, Equatable {
    var enabled = true
    var activationAngle = 105.0
    var fullStrengthAngle = 25.0
    var maxLeanDegrees = 50.0
    var perspective = 0.6
    var maxBlur = 28.0
    var blurGamma = 1.6
    var maxDim = 0.95
    var easeCurve = EaseCurve.smoothstep
    var smoothingMs = 80.0
    var leanDirection = 1
    var showAngleInMenuBar = false

    static let defaults = EffectParameters()

    enum Range {
        static let activationAngle: ClosedRange<Double> = 40...150
        static let fullStrengthAngle: ClosedRange<Double> = 0...90
        static let maxLeanDegrees: ClosedRange<Double> = 0...80
        static let perspective: ClosedRange<Double> = 0...1
        static let maxBlur: ClosedRange<Double> = 0...80
        static let blurGamma: ClosedRange<Double> = 0.5...3
        static let maxDim: ClosedRange<Double> = 0...1
        static let smoothingMs: ClosedRange<Double> = 0...300
    }

    /// Minimum gap kept between `fullStrengthAngle` and `activationAngle`.
    static let minimumRampDegrees = 1.0

    init() {}

    /// Values forced into their ranges, with `fullStrengthAngle < activationAngle`.
    func clamped() -> EffectParameters {
        var p = self
        p.activationAngle = p.activationAngle.clamped(to: Range.activationAngle)
        p.fullStrengthAngle = p.fullStrengthAngle.clamped(to: Range.fullStrengthAngle)
        if p.fullStrengthAngle > p.activationAngle - Self.minimumRampDegrees {
            p.fullStrengthAngle = p.activationAngle - Self.minimumRampDegrees
        }
        p.maxLeanDegrees = p.maxLeanDegrees.clamped(to: Range.maxLeanDegrees)
        p.perspective = p.perspective.clamped(to: Range.perspective)
        p.maxBlur = p.maxBlur.clamped(to: Range.maxBlur)
        p.blurGamma = p.blurGamma.clamped(to: Range.blurGamma)
        p.maxDim = p.maxDim.clamped(to: Range.maxDim)
        p.smoothingMs = p.smoothingMs.clamped(to: Range.smoothingMs)
        p.leanDirection = p.leanDirection < 0 ? -1 : 1
        return p
    }

    // Decoding is per key with fallback to the default, so adding, removing or
    // corrupting one key never throws away the rest of the user's settings.
    private enum CodingKeys: String, CodingKey {
        case enabled, activationAngle, fullStrengthAngle, maxLeanDegrees, perspective, maxBlur,
             blurGamma, maxDim, easeCurve, smoothingMs, leanDirection, showAngleInMenuBar
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EffectParameters.defaults
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        enabled = get(.enabled, d.enabled)
        activationAngle = get(.activationAngle, d.activationAngle)
        fullStrengthAngle = get(.fullStrengthAngle, d.fullStrengthAngle)
        maxLeanDegrees = get(.maxLeanDegrees, d.maxLeanDegrees)
        perspective = get(.perspective, d.perspective)
        maxBlur = get(.maxBlur, d.maxBlur)
        blurGamma = get(.blurGamma, d.blurGamma)
        maxDim = get(.maxDim, d.maxDim)
        easeCurve = get(.easeCurve, d.easeCurve)
        smoothingMs = get(.smoothingMs, d.smoothingMs)
        leanDirection = get(.leanDirection, d.leanDirection)
        showAngleInMenuBar = get(.showAngleInMenuBar, d.showAngleInMenuBar)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
