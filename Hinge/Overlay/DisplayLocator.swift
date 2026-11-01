import AppKit

/// Tracks the built-in display. `builtInScreen` is nil when it is inactive
/// (clamshell) or absent.
final class DisplayLocator {
    var onChange: (() -> Void)?
    private(set) var builtInScreen: NSScreen?
    private var observer: NSObjectProtocol?

    init() {
        builtInScreen = Self.findBuiltIn()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.builtInScreen = Self.findBuiltIn()
            self.onChange?()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    static func findBuiltIn() -> NSScreen? {
        NSScreen.screens.first { screen in
            displayID(of: screen).map { CGDisplayIsBuiltin($0) != 0 } ?? false
        }
    }
}
