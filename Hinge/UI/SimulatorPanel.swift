import AppKit

/// Floating, non-activating panel with an angle slider. Sits above the overlay
/// so it is never blurred or dimmed.
final class SimulatorPanel: NSPanel, NSWindowDelegate {
    static let defaultAngle = 120.0

    var onSimulatedAngle: ((Double) -> Void)?
    var onUseRealSensor: ((Bool) -> Void)?
    var onClose: (() -> Void)?

    private let slider = NSSlider(value: defaultAngle, minValue: 0, maxValue: 180, target: nil, action: nil)
    private let angleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let realSensorCheckbox = NSButton(checkboxWithTitle: "Use real sensor", target: nil, action: nil)

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 116),
                   styleMask: [.titled, .closable, .utilityWindow, .hudWindow, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "Simulate lid angle"
        // isFloatingPanel resets `level` to .floating, so it must come first.
        isFloatingPanel = true
        level = OverlayWindow.aboveOverlayLevel
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self
        buildContent()
        setUsingRealSensor(false)
    }

    private func buildContent() {
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.isContinuous = true
        slider.controlSize = .regular

        angleLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        angleLabel.alignment = .right
        detailLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor

        realSensorCheckbox.target = self
        realSensorCheckbox.action = #selector(checkboxToggled)

        let top = NSStackView(views: [slider, angleLabel])
        top.orientation = .horizontal
        top.spacing = 12
        angleLabel.setContentHuggingPriority(.required, for: .horizontal)
        angleLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let bottom = NSStackView(views: [realSensorCheckbox, NSView(), detailLabel])
        bottom.orientation = .horizontal

        let stack = NSStackView(views: [top, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        top.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        bottom.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentView = container
        updateLabel(angle: slider.doubleValue)
    }

    /// Place near the bottom centre of `screen` and show without activating the app.
    func present(on screen: NSScreen?) {
        if !isVisible, let screen {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.minY + 80))
        }
        orderFrontRegardless()
        // The overlay lives in the above-lock-screen space; join it so the
        // panel's higher level still puts it on top of the effect. Done after
        // ordering in, when the panel is guaranteed to have a window number.
        LockScreenSpace.adopt(self)
    }

    var simulatedAngle: Double { slider.doubleValue }

    func setSimulatedAngle(_ angle: Double) {
        slider.doubleValue = angle
        updateLabel(angle: angle)
    }

    /// Live readout: the angle that is actually driving the effect.
    func show(liveAngle: Double, progress: Double) {
        if realSensorCheckbox.state == .on { slider.doubleValue = liveAngle }
        updateLabel(angle: liveAngle)
        detailLabel.stringValue = progress > 0 ? String(format: "effect %3.0f%%", progress * 100) : "effect off"
    }

    func setUsingRealSensor(_ on: Bool) {
        realSensorCheckbox.state = on ? .on : .off
        slider.isEnabled = !on
    }

    private func updateLabel(angle: Double) {
        angleLabel.stringValue = String(format: "%.0f°", angle)
    }

    @objc private func sliderMoved() {
        updateLabel(angle: slider.doubleValue)
        onSimulatedAngle?(slider.doubleValue)
    }

    @objc private func checkboxToggled() {
        let on = realSensorCheckbox.state == .on
        slider.isEnabled = !on
        onUseRealSensor?(on)
        if !on { onSimulatedAngle?(slider.doubleValue) }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
