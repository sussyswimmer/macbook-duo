import Foundation

/// Anything that can publish a lid angle. The real sensor and the simulator
/// both conform, so everything downstream is source-agnostic.
protocol AngleSource: AnyObject {
    /// Called on the main thread with the angle in degrees (0 = closed).
    var onAngle: ((Double) -> Void)? { get set }
    /// Starts publishing, or changes the rate if already running.
    func start(rateHz: Double)
    func stop()
}
