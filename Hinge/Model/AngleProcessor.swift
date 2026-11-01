import Foundation

/// Deadband + critically-damped spring smoothing for the raw lid angle.
///
/// Pure value type: feed samples with `step(input:dt:)`, read `output`.
/// The spring is integrated with its exact closed-form solution, so the result
/// is independent of the step size (30 / 60 / 120 Hz all land on the same curve
/// for a piecewise-constant input).
struct AngleProcessor {
    /// Input changes smaller than this (degrees) are treated as jitter.
    var deadband: Double = 0.3
    /// Response time. After `smoothingMs` a step is ~91% complete, after 3× it
    /// is fully settled for practical purposes. 0 = no smoothing.
    var smoothingMs: Double

    private(set) var output: Double?
    private(set) var target: Double?
    private(set) var velocity: Double = 0

    init(smoothingMs: Double = 80, deadband: Double = 0.3) {
        self.smoothingMs = smoothingMs
        self.deadband = deadband
    }

    /// Spring angular frequency (1/s). ω = 4 / T gives ~91% at t = T.
    var omega: Double { smoothingMs > 0 ? 4.0 / (smoothingMs / 1000.0) : .infinity }

    var isSettled: Bool {
        guard let output, let target else { return true }
        return abs(output - target) < 0.01 && abs(velocity) < 0.01
    }

    /// Jump straight to `value` with no animation.
    mutating func reset(to value: Double) {
        output = value
        target = value
        velocity = 0
    }

    /// Accept a new raw sample (subject to the deadband) and advance by `dt` seconds.
    @discardableResult
    mutating func step(input: Double, dt: Double) -> Double {
        guard let current = output, let oldTarget = target else {
            reset(to: input)
            return input
        }
        if abs(input - oldTarget) >= deadband {
            target = input
        }
        return advance(from: current, dt: dt)
    }

    /// Advance without a new sample (e.g. to keep animating between polls).
    @discardableResult
    mutating func advance(dt: Double) -> Double {
        guard let current = output else { return 0 }
        return advance(from: current, dt: dt)
    }

    private mutating func advance(from current: Double, dt: Double) -> Double {
        guard let target else { return current }
        let w = omega
        guard w.isFinite, dt > 0 else {
            if !w.isFinite { output = target; velocity = 0 }
            return output ?? target
        }
        // Exact solution of y'' = -w² y - 2w y' with y = x - target.
        let y0 = current - target
        let v0 = velocity
        let decay = exp(-w * dt)
        let c = v0 + w * y0
        let y = (y0 + c * dt) * decay
        let v = (v0 - w * c * dt) * decay
        output = target + y
        velocity = v
        return output!
    }
}
