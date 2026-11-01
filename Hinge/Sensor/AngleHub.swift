import QuartzCore
import os

/// Owns the real and simulated sources, runs the active one through the
/// `AngleProcessor`, and publishes the smoothed angle. Main thread only.
///
/// Time advances on every sample *and* on every `tick()` (display frame), using
/// one shared clock, so the spring animates at display rate between samples
/// without ever double-counting time.
final class AngleHub {
    enum Source { case sensor, simulator }

    let sensor = LidSensor()
    let simulator = SimulatedAngleSource()

    /// Smoothed angle, after every sample and every tick.
    var onAngle: ((Double) -> Void)?
    /// A fresh sample arrived (called before `onAngle`).
    var onSample: (() -> Void)?

    private(set) var source: Source = .sensor
    private(set) var rateHz: Double = 0
    /// Last unsmoothed sample from the active source.
    private(set) var latestInput: Double?
    var smoothed: Double? { processor.output }
    /// `CACurrentMediaTime()` of the last sample (does not advance during sleep).
    private(set) var lastSampleTime: CFTimeInterval?
    var isSettled: Bool { processor.isSettled }

    private let log = Logger(subsystem: "com.maxwell.hinge", category: "AngleHub")
    private var processor: AngleProcessor
    private var lastAdvance: CFTimeInterval?

    init(smoothingMs: Double) {
        processor = AngleProcessor(smoothingMs: smoothingMs)
        sensor.onAngle = { [weak self] deg in
            guard let self, self.source == .sensor else { return }
            self.ingest(deg)
        }
        simulator.onAngle = { [weak self] deg in
            guard let self, self.source == .simulator else { return }
            self.ingest(deg)
        }
    }

    var smoothingMs: Double {
        get { processor.smoothingMs }
        set { processor.smoothingMs = newValue }
    }

    /// Switch sources. The processor keeps its state, so the effect glides to
    /// the new source's angle instead of jumping.
    func setSource(_ newSource: Source) {
        guard newSource != source else { return }
        log.info("source → \(newSource == .sensor ? "sensor" : "simulator", privacy: .public)")
        activeSource.stop()
        source = newSource
        latestInput = nil
        applyRate()
    }

    /// 0 stops polling.
    func setRate(_ hz: Double) {
        guard hz != rateHz else { return }
        rateHz = hz
        applyRate()
    }

    /// After wake: forget timing so the first sample isn't measured against
    /// pre-sleep time, and get a fresh handle on the sensor.
    func systemDidWake() {
        lastAdvance = nil
        lastSampleTime = nil
        if source == .sensor, rateHz > 0 { sensor.reopen() }
    }

    func stopAll() {
        sensor.stop()
        simulator.stop()
        rateHz = 0
    }

    /// Advance the smoothing to "now" without a new sample.
    func tick() {
        guard processor.output != nil else { return }
        let out = processor.advance(dt: elapsed())
        onAngle?(out)
    }

    private var activeSource: AngleSource {
        source == .sensor ? sensor : simulator
    }

    private func applyRate() {
        let inactive: AngleSource = source == .sensor ? simulator : sensor
        inactive.stop()
        if rateHz > 0 {
            activeSource.start(rateHz: rateHz)
        } else {
            activeSource.stop()
            lastAdvance = nil
        }
    }

    private func elapsed() -> Double {
        let now = CACurrentMediaTime()
        defer { lastAdvance = now }
        return lastAdvance.map { now - $0 } ?? 0
    }

    private func ingest(_ degrees: Double) {
        latestInput = degrees
        lastSampleTime = CACurrentMediaTime()
        onSample?()
        // The new reading only becomes known now: spend the time since the last
        // update on the *old* target, then retarget. Otherwise a long gap (4 Hz
        // polling) is spent chasing the new angle and the effect pops in at
        // full strength instead of animating on the display clock.
        processor.advance(dt: elapsed())
        let out = processor.step(input: degrees, dt: 0)
        onAngle?(out)
    }
}
