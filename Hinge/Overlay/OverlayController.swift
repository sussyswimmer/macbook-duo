import AppKit
import os

/// Phase 1 renderer. Covers the built-in display with a stack of horizontal
/// strip windows. Each strip blurs what is behind it with a window-server blur
/// whose radius follows `blurAt(v)` at the strip's height, and tints it black
/// at the current dim. No windows are on screen while the effect is inactive.
final class OverlayController {
    /// Vertical resolution of the graduated blur.
    static let stripCount = 24
    /// Window background alpha. A fully transparent window gets no backdrop
    /// blur; 1/255 black is invisible as a tint.
    static let minimumBackgroundAlpha = 1.0 / 255.0

    private let log = Logger(subsystem: "com.maxwell.hinge", category: "Overlay")
    private let locator: DisplayLocator
    private var strips: [OverlayWindow] = []   // index 0 = bottom
    private var appliedRadii: [Int] = []
    private var appliedAlpha: Double = -1
    private var stripScreenFrame: NSRect = .zero
    private var lastState: EffectState = .inactive
    private(set) var isVisible = false

    init(locator: DisplayLocator) {
        self.locator = locator
    }

    func update(_ state: EffectState) {
        lastState = state
        guard state.isActive, let screen = locator.builtInScreen else {
            hide()
            return
        }
        layoutStrips(for: screen.frame)
        if !isVisible {
            log.info("overlay shown (p=\(state.p, format: .fixed(precision: 3), privacy: .public))")
            // Bottom first so ordering is stable; all share one level.
            for w in strips { w.orderFrontRegardless() }
            isVisible = true
        }
        apply(state)
    }

    /// Display configuration changed: re-fit (or drop) the windows.
    func screensChanged() {
        if let screen = locator.builtInScreen, !strips.isEmpty {
            layoutStrips(for: screen.frame)
        }
        update(lastState)
    }

    func hide() {
        guard isVisible else { return }
        log.info("overlay hidden")
        for w in strips { w.orderOut(nil) }
        isVisible = false
        // Force a full re-apply next time (radii are window-server state).
        appliedRadii = Array(repeating: -1, count: strips.count)
        appliedAlpha = -1
    }

    /// Tear down completely (quit).
    func teardown() {
        for w in strips {
            WindowServerBlur.setRadius(0, on: w)
            w.orderOut(nil)
            w.close()
        }
        strips = []
        appliedRadii = []
        isVisible = false
    }

    // MARK: Private

    private func apply(_ state: EffectState) {
        for i in strips.indices {
            let v = (Double(i) + 0.5) / Double(strips.count)
            let r = Int(state.blurAt(v).rounded())
            if r != appliedRadii[i], WindowServerBlur.setRadius(r, on: strips[i]) {
                appliedRadii[i] = r
            }
        }
        // Dim is a Core Animation opacity change: no AppKit redraw per frame.
        if abs(state.dim - appliedAlpha) > 0.0005 {
            appliedAlpha = state.dim
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for w in strips { w.contentView?.layer?.opacity = Float(state.dim) }
            CATransaction.commit()
        }
    }

    private func layoutStrips(for frame: NSRect) {
        if strips.isEmpty {
            strips = (0..<Self.stripCount).map { _ in
                let w = OverlayWindow(frame: .zero)
                // A fully clear window gets no backdrop blur; 1/255 black is invisible.
                w.backgroundColor = NSColor(white: 0, alpha: Self.minimumBackgroundAlpha)
                let dim = NSView()
                dim.wantsLayer = true
                dim.layer?.backgroundColor = NSColor.black.cgColor
                dim.layer?.opacity = 0
                w.contentView = dim
                return w
            }
            appliedRadii = Array(repeating: -1, count: strips.count)
        }
        guard frame != stripScreenFrame else { return }
        stripScreenFrame = frame
        let n = strips.count
        // Integer point boundaries so neighbouring strips never overlap or gap.
        func edge(_ i: Int) -> CGFloat { (frame.height * CGFloat(i) / CGFloat(n)).rounded() }
        for (i, w) in strips.enumerated() {
            let r = NSRect(x: frame.minX, y: frame.minY + edge(i),
                           width: frame.width, height: edge(i + 1) - edge(i))
            w.setFrame(r, display: false)
        }
    }
}
