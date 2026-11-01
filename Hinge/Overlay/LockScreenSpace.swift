import AppKit
import os

/// A window-server space at an absolute level above the lock screen. Windows
/// moved into it stay visible over the login/lock screen and over every
/// normal and full-screen space.
///
/// Private SkyLight SPI, looked up with dlsym so a missing symbol only means
/// "overlay stays below the lock screen". Approach learned from
/// Lakr233/SkyLightWindow (MIT); this is our own implementation.
enum LockScreenSpace {
    /// Absolute space levels used by the window server.
    private enum Level: Int32 {
        case screenLock = 300
        case notificationCenterAtScreenLock = 400
    }

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    private static let log = Logger(subsystem: "com.maxwell.hinge", category: "LockScreenSpace")

    private struct API {
        let connection: Int32
        let space: Int32
        let addWindows: AddWindows
        let copySpaces: CopySpacesForWindows?
    }

    private static let api: API? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let mainConnection = dlsym(h, "SLSMainConnectionID"),
              let create = dlsym(h, "SLSSpaceCreate"),
              let setLevel = dlsym(h, "SLSSpaceSetAbsoluteLevel"),
              let show = dlsym(h, "SLSShowSpaces"),
              let add = dlsym(h, "SLSSpaceAddWindowsAndRemoveFromSpaces") else {
            log.error("SkyLight space SPI unavailable; overlay will stay below the lock screen")
            return nil
        }
        let cid = unsafeBitCast(mainConnection, to: MainConnection.self)()
        let space = unsafeBitCast(create, to: SpaceCreate.self)(cid, 1, 0)
        guard space != 0 else {
            log.error("SLSSpaceCreate failed")
            return nil
        }
        let levelErr = unsafeBitCast(setLevel, to: SpaceSetAbsoluteLevel.self)(
            cid, space, Level.notificationCenterAtScreenLock.rawValue)
        let showErr = unsafeBitCast(show, to: ShowSpaces.self)(cid, [space] as CFArray)
        log.info("created space \(space, privacy: .public) (level err \(levelErr, privacy: .public), show err \(showErr, privacy: .public))")
        return API(connection: cid, space: space,
                   addWindows: unsafeBitCast(add, to: AddWindows.self),
                   copySpaces: dlsym(h, "SLSCopySpacesForWindows").map { unsafeBitCast($0, to: CopySpacesForWindows.self) })
    }()

    static var isAvailable: Bool { api != nil }

    /// Move `window` into the space. Call once, after the window exists.
    @discardableResult
    static func adopt(_ window: NSWindow) -> Bool {
        guard let api else { return false }
        guard window.windowNumber > 0 else {
            log.error("adopt: window has no window number yet")
            return false
        }
        // 7 = "remove from all other spaces".
        let err = api.addWindows(api.connection, api.space, [window.windowNumber] as CFArray, 7)
        if err != 0 { log.error("adopt window failed: \(err, privacy: .public)") }
        return err == 0
    }

    /// Diagnostics: is `window` currently in our space?
    static func contains(_ window: NSWindow) -> Bool? {
        guard let api, let copy = api.copySpaces,
              // Selector 7 returns nothing for these spaces; 0xFFFF = all spaces.
              let spaces = copy(api.connection, 0xFFFF, [window.windowNumber] as CFArray)?.takeRetainedValue() as? [NSNumber]
        else { return nil }
        return spaces.contains { $0.int32Value == api.space }
    }
}
