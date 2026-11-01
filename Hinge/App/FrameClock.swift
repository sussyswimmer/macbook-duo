import AppKit
import QuartzCore

/// A display-synced tick (CADisplayLink from the built-in screen, macOS 14+).
/// Runs only while something is animating.
final class FrameClock: NSObject {
    var onFrame: (() -> Void)?
    private var link: CADisplayLink?
    private weak var screen: NSScreen?

    var isRunning: Bool { link.map { !$0.isPaused } ?? false }

    func run(on screen: NSScreen?) {
        guard let screen else { stop(); return }
        if link == nil || self.screen !== screen {
            link?.invalidate()
            let l = screen.displayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            link = l
            self.screen = screen
        }
        link?.isPaused = false
    }

    func pause() {
        link?.isPaused = true
    }

    func stop() {
        link?.invalidate()
        link = nil
        screen = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        onFrame?()
    }
}
