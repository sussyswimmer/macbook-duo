import Foundation
import IOKit.hid
import os

/// Reads the MacBook lid-angle sensor (an IOKit HID "orientation" device on the
/// sensor hub) by polling feature report 1.
final class LidSensor: AngleSource {
    /// Raw 16-bit value → degrees. Verified in Phase 0: the raw value is whole
    /// degrees (see DECISIONS.md).
    static let rawToDegrees = 1.0

    enum State: Equatable {
        case idle
        case running
        case notFound
        case openFailed(IOReturn)
        case readFailed(IOReturn)

        var message: String? {
            switch self {
            case .idle, .running: return nil
            case .notFound: return "No lid angle sensor found"
            case .openFailed(let r): return String(format: "Lid sensor could not be opened (0x%08x)", r)
            case .readFailed(let r): return String(format: "Lid sensor read failed (0x%08x)", r)
            }
        }
    }

    var onAngle: ((Double) -> Void)?
    /// Raw value, for debugging. Main thread.
    var onRaw: ((UInt16) -> Void)?
    /// State changes. Main thread.
    var onStateChange: ((State) -> Void)?

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    private let log = Logger(subsystem: "com.maxwell.hinge", category: "LidSensor")
    private let queue = DispatchQueue(label: "com.maxwell.hinge.lidsensor", qos: .utility)
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private var currentRate: Double = 0
    private var consecutiveFailures = 0

    deinit {
        timer?.cancel()
        closeDevice()
    }

    // MARK: AngleSource

    func start(rateHz: Double) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard rateHz > 0 else { stop(); return }
        if device == nil, !openDevice() { return }
        if timer != nil, rateHz == currentRate { return }
        currentRate = rateHz
        timer?.cancel()

        let t = DispatchSource.makeTimerSource(queue: queue)
        let interval = 1.0 / rateHz
        // Generous leeway at low rates lets the system coalesce wake-ups.
        let leeway = DispatchTimeInterval.milliseconds(rateHz <= 10 ? 50 : 2)
        t.schedule(deadline: .now(), repeating: interval, leeway: leeway)
        t.setEventHandler { [weak self] in self?.poll() }
        timer = t
        t.resume()
        state = .running
        log.info("polling at \(rateHz, privacy: .public) Hz")
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        timer?.cancel()
        timer = nil
        currentRate = 0
        if state == .running { state = .idle }
    }

    /// One synchronous read. Returns nil if the device is unavailable.
    func readOnce() -> (raw: UInt16, degrees: Double)? {
        guard let device else { return nil }
        return Self.read(device).value
    }

    // MARK: Device

    private func openDevice() -> Bool {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDProductIDKey: 0x8104,
            kIOHIDPrimaryUsagePageKey: 0x20, // Sensor
            kIOHIDPrimaryUsageKey: 0x8A,     // Orientation
        ]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)
        let mres = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if mres != kIOReturnSuccess {
            log.error("IOHIDManagerOpen failed: \(mres, privacy: .public)")
        }
        guard let devices = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>,
              let dev = devices.first else {
            log.error("no lid angle sensor matched")
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
            state = .notFound
            return false
        }
        let dres = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard dres == kIOReturnSuccess else {
            log.error("IOHIDDeviceOpen failed: \(dres, privacy: .public)")
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
            state = .openFailed(dres)
            return false
        }
        manager = mgr
        device = dev
        consecutiveFailures = 0
        return true
    }

    private func closeDevice() {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        manager = nil
    }

    private enum ReadResult {
        case ok(UInt16, Double)
        case failed(IOReturn)
        var value: (raw: UInt16, degrees: Double)? {
            if case .ok(let r, let d) = self { return (r, d) }
            return nil
        }
    }

    private static func read(_ device: IOHIDDevice) -> ReadResult {
        var buf = [UInt8](repeating: 0, count: 8)
        var len = CFIndex(buf.count)
        let r = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &buf, &len)
        guard r == kIOReturnSuccess, len >= 3 else { return .failed(r) }
        let raw = UInt16(buf[1]) | UInt16(buf[2]) << 8
        return .ok(raw, Double(raw) * rawToDegrees)
    }

    /// Runs on `queue`.
    private func poll() {
        guard let device else { return }
        let result = Self.read(device)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.timer != nil else { return }
            switch result {
            case .ok(let raw, let deg):
                self.consecutiveFailures = 0
                if self.state != .running { self.state = .running }
                self.onRaw?(raw)
                self.onAngle?(deg)
            case .failed(let r):
                self.consecutiveFailures += 1
                if self.consecutiveFailures == 1 {
                    self.log.error("feature report read failed: \(r, privacy: .public)")
                }
                if self.consecutiveFailures >= 10 { self.state = .readFailed(r) }
            }
        }
    }
}
