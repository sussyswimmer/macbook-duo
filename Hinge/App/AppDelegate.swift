import AppKit
import Combine
import os

/// Wires sensor → model → overlay, and the menu/simulator UI.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.maxwell.hinge", category: "App")
    private let store = ParameterStore()
    private lazy var hub = AngleHub(smoothingMs: store.params.smoothingMs)
    private let locator = DisplayLocator()
    private lazy var overlay = OverlayController(locator: locator)
    private var menuBar: MenuBarController!
    private var simulatorPanel: SimulatorPanel?
    private var panelWasVisibleBeforeLock = false
    private var cancellables: Set<AnyCancellable> = []
    private var state: EffectState = .inactive
    private let clock = FrameClock()
    private var watchdog: DispatchSourceTimer?
    /// Set when the overlay was pulled because samples stopped; cleared by the next sample.
    private var samplesStale = false
    /// Overlay is withdrawn if it is up and no sample has arrived for this long.
    static let staleSampleTimeout: CFTimeInterval = 2

    private var params: EffectParameters { store.params }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
        menuBar.currentFlags = { [weak self] in
            (self?.params.enabled ?? false, self?.params.showAngleInMenuBar ?? false)
        }
        menuBar.onToggleEnabled = { [weak self] in self?.store.params.enabled.toggle() }
        menuBar.onToggleShowAngle = { [weak self] in self?.store.params.showAngleInMenuBar.toggle() }
        menuBar.onSimulate = { [weak self] in self?.openSimulator() }

        hub.onAngle = { [weak self] θ in self?.angleChanged(θ) }
        hub.onSample = { [weak self] in self?.samplesStale = false }
        clock.onFrame = { [weak self] in self?.hub.tick() }
        hub.sensor.onStateChange = { [weak self] s in
            self?.log.info("sensor state: \(String(describing: s), privacy: .public)")
            self?.refreshStatus()
        }
        locator.onChange = { [weak self] in
            guard let self else { return }
            self.log.info("screens changed; built-in present: \(self.locator.builtInScreen != nil, privacy: .public)")
            self.overlay.screensChanged()
            self.clock.stop() // re-created on the right screen when next needed
            self.updateClock()
            self.refreshStatus()
        }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemDidWake()
        }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLockChanged(locked: true)
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLockChanged(locked: false)
        }

        store.$params
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // @Published fires in willSet; defer one turn so reads see the new value.
                DispatchQueue.main.async { self?.paramsChanged() }
            }
            .store(in: &cancellables)

        paramsChanged()

        // QA hook: `open Hinge.app --args -debugSimAngle 60` starts in the simulator.
        if UserDefaults.standard.object(forKey: "debugSimAngle") != nil {
            openSimulator(angle: UserDefaults.standard.double(forKey: "debugSimAngle"))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the screen dimmed.
        overlay.teardown()
        watchdog?.cancel()
        clock.stop()
        hub.stopAll()
    }

    // MARK: Flow

    private func paramsChanged() {
        hub.smoothingMs = params.smoothingMs
        menuBar.refreshChecks(enabled: params.enabled, showAngle: params.showAngleInMenuBar)
        updateRate()
        if let θ = hub.smoothed { angleChanged(θ) } else { render(.inactive) }
        if !params.showAngleInMenuBar { menuBar.setAngle(nil) }
        refreshStatus()
    }

    private func angleChanged(_ θ: Double) {
        render(EffectModel.evaluate(angle: θ, params: params))
        if params.showAngleInMenuBar { menuBar.setAngle(θ) }
        simulatorPanel?.show(liveAngle: θ, progress: state.p)
        updateRate()
        updateClock()
    }

    /// Display-rate animation only while the spring is moving near the active zone.
    private func updateClock() {
        if hub.rateHz > PollingPolicy.idleHz, !hub.isSettled {
            if !clock.isRunning { clock.run(on: locator.builtInScreen) }
        } else if clock.isRunning {
            clock.pause()
        }
    }

    private func render(_ newState: EffectState) {
        state = newState
        overlay.update(samplesStale ? .inactive : newState)
        updateWatchdog()
    }

    // MARK: Safety

    /// While the overlay is up, check twice a second that samples keep coming.
    /// If they stop (sensor lost, stuck after wake) the overlay is withdrawn so
    /// the screen — including the lock screen — is never left dimmed.
    private func updateWatchdog() {
        if overlay.isVisible {
            guard watchdog == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: .main)
            t.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
            t.setEventHandler { [weak self] in self?.checkSamplesFresh() }
            watchdog = t
            t.resume()
        } else if let t = watchdog {
            t.cancel()
            watchdog = nil
        }
    }

    private func checkSamplesFresh() {
        let age = hub.lastSampleTime.map { CACurrentMediaTime() - $0 } ?? .infinity
        guard age > Self.staleSampleTimeout, overlay.isVisible else { return }
        log.error("no lid samples for \(age, format: .fixed(precision: 1), privacy: .public) s; withdrawing overlay")
        samplesStale = true
        render(state)
    }

    private func systemDidWake() {
        log.info("system did wake")
        clock.stop()         // display link is re-created on the right screen
        hub.systemDidWake()  // fresh sensor handle; samples resume within a frame
        updateRate()
    }

    private func screenLockChanged(locked: Bool) {
        log.info("screen \(locked ? "locked" : "unlocked", privacy: .public)")
        // The panel lives above the lock screen with the overlay; keep it off
        // the lock screen itself.
        guard let panel = simulatorPanel else { return }
        if locked {
            panelWasVisibleBeforeLock = panel.isVisible
            panel.orderOut(nil)
        } else if panelWasVisibleBeforeLock {
            panel.orderFrontRegardless()
        }
    }

    /// Adaptive polling. Uses the lower of the raw and smoothed angle so fast
    /// polling continues until the effect has fully unwound.
    private func updateRate() {
        let candidates = [hub.latestInput, hub.smoothed].compactMap { $0 }
        let angle = candidates.min()
        var rate = PollingPolicy.rate(angle: angle, params: params, current: hub.rateHz)
        // While the simulator is open, keep it responsive regardless.
        if hub.source == .simulator, rate > 0 { rate = PollingPolicy.activeHz }
        hub.setRate(rate)
    }

    private func refreshStatus() {
        var messages: [String] = []
        if let m = hub.sensor.state.message { messages.append(m) }
        if locator.builtInScreen == nil { messages.append("Built-in display is off") }
        menuBar.setStatus(messages.isEmpty ? nil : messages.joined(separator: " · "))
    }

    // MARK: Simulator

    private func openSimulator(angle: Double? = nil) {
        let panel = simulatorPanel ?? makeSimulatorPanel()
        simulatorPanel = panel
        if let angle { panel.setSimulatedAngle(angle) }
        if !panel.isVisible {
            hub.simulator.angle = panel.simulatedAngle
            panel.setUsingRealSensor(false)
            hub.setSource(.simulator)
            updateRate()
        }
        panel.present(on: locator.builtInScreen ?? NSScreen.main)
    }

    private func makeSimulatorPanel() -> SimulatorPanel {
        let panel = SimulatorPanel()
        panel.onSimulatedAngle = { [weak self] a in self?.hub.simulator.angle = a }
        panel.onUseRealSensor = { [weak self] real in
            guard let self else { return }
            self.log.info("use real sensor: \(real, privacy: .public)")
            self.hub.setSource(real ? .sensor : .simulator)
            self.updateRate()
        }
        panel.onClose = { [weak self] in
            guard let self else { return }
            self.log.info("simulator closed")
            self.hub.setSource(.sensor)
            self.updateRate()
        }
        return panel
    }
}
