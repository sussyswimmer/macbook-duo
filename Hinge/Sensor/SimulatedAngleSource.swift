import Foundation

/// An `AngleSource` driven by a slider. Re-emits its current value at the
/// requested rate (so the smoothing keeps animating after the slider stops)
/// and immediately whenever the value changes.
final class SimulatedAngleSource: AngleSource {
    var onAngle: ((Double) -> Void)?

    var angle: Double = 120 {
        didSet { if timer != nil { onAngle?(angle) } }
    }

    private var timer: DispatchSourceTimer?
    private var currentRate: Double = 0

    func start(rateHz: Double) {
        guard rateHz > 0 else { stop(); return }
        if timer != nil, rateHz == currentRate { return }
        currentRate = rateHz
        timer?.cancel()
        // Main queue: GCD's main queue is serviced in the common run-loop modes,
        // so this keeps firing while a slider is being dragged.
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 1.0 / rateHz, leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.onAngle?(self.angle)
        }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        currentRate = 0
    }

    deinit { timer?.cancel() }
}
