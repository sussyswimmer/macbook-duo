import AppKit

/// Borderless, click-through, focus-less window covering one display above
/// everything (including full-screen spaces and the menu bar).
final class OverlayWindow: NSWindow {
    /// Our own UI (simulator, preferences) sits one level above this.
    static let overlayLevel = NSWindow.Level.screenSaver
    static let aboveOverlayLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = Self.overlayLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        // Allowed to be on screen while the session is locked.
        canBecomeVisibleWithoutLogin = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
