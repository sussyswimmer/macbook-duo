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
    private var cancellables: Set<AnyCancellable> = []
    private var state: EffectState = .inactive
    private let clock = FrameClock()

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
        overlay.update(newState)
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
