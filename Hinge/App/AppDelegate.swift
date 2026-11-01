import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.maxwell.hinge", category: "App")
    private var menuBar: MenuBarController!
    private let sensor = LidSensor()
    private var processor = AngleProcessor(smoothingMs: 80)
    private var lastSample: CFTimeInterval?
    private var lastRaw: UInt16?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()

        sensor.onRaw = { [weak self] raw in self?.lastRaw = raw }
        sensor.onAngle = { [weak self] deg in self?.handle(angle: deg) }
        sensor.onStateChange = { [weak self] state in
            guard let self else { return }
            self.log.info("sensor state: \(String(describing: state), privacy: .public)")
            self.menuBar.setStatus(state.message)
        }
        // Phase 0: fixed debug rate. Adaptive polling arrives in Phase 1.
        sensor.start(rateHz: 10)
        menuBar.setStatus(sensor.state.message)
    }

    private func handle(angle: Double) {
        let now = CACurrentMediaTime()
        let dt = lastSample.map { now - $0 } ?? 0
        lastSample = now
        let smoothed = processor.step(input: angle, dt: dt)
        if let raw = lastRaw {
            menuBar.setDebug(raw: raw, degrees: smoothed)
            log.debug("raw=\(raw, privacy: .public) deg=\(smoothed, format: .fixed(precision: 1), privacy: .public)")
        }
    }
}
