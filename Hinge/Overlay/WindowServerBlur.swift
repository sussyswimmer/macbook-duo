import AppKit
import os

/// Thin wrapper around the window server's per-window background blur
/// (`CGSSetWindowBackgroundBlurRadius`, private SPI, same call terminal apps use
/// for blurred backgrounds). Looked up with dlsym so a missing symbol degrades
/// to "dim only" instead of failing to launch. See DECISIONS.md, Phase 1.
enum WindowServerBlur {
    private typealias MainConnection = @convention(c) () -> UInt32
    private typealias SetRadius = @convention(c) (UInt32, UInt32, Int32) -> Int32

    private static let log = Logger(subsystem: "com.maxwell.hinge", category: "Blur")

    private static let functions: (MainConnection, SetRadius)? = {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let c = dlsym(handle, "CGSMainConnectionID"),
              let s = dlsym(handle, "CGSSetWindowBackgroundBlurRadius") else {
            log.error("window-server blur SPI not available; blur disabled")
            return nil
        }
        return (unsafeBitCast(c, to: MainConnection.self), unsafeBitCast(s, to: SetRadius.self))
    }()

    static var isAvailable: Bool { functions != nil }

    /// Radius in points (the window server scales for Retina). Returns success.
    @discardableResult
    static func setRadius(_ radius: Int, on window: NSWindow) -> Bool {
        guard let (connection, setRadius) = functions, window.windowNumber > 0 else { return false }
        let err = setRadius(connection(), UInt32(window.windowNumber), Int32(max(0, radius)))
        if err != 0 { log.error("set blur radius failed: \(err, privacy: .public)") }
        return err == 0
    }
}
