import AppKit

/// Puts a window into a private window-server space that stays composited over
/// the lock screen.
///
/// Window level alone cannot do this: loginwindow draws above every level a
/// user-space app can set, which is why raising ours to the shield, cursor and
/// even maximum level all still got covered. The window server does, however,
/// support spaces with an *absolute level*, and the one Notification Center
/// uses while the screen is locked (400) survives the lock. So the trick is to
/// create such a space once and move the window into it.
///
/// This relies on SkyLight, a private framework, so every symbol is resolved at
/// runtime and any failure degrades to "no lock screen card" rather than a crash.
enum SkyLightSpace {
    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias SpaceCreateFn = @convention(c) (Int32, Int, Int) -> UInt64
    private typealias SpaceSetAbsoluteLevelFn = @convention(c) (Int32, UInt64, Int32) -> Void
    private typealias ShowSpacesFn = @convention(c) (Int32, CFArray) -> Void
    private typealias AddWindowsFn = @convention(c) (Int32, UInt64, CFArray, Int32) -> Void

    /// Absolute level of Notification Center while the screen is locked.
    private static let lockScreenAbsoluteLevel: Int32 = 400
    /// Selector meaning "add to this space, remove from the others".
    private static let moveSelector: Int32 = 7

    private static var connection: Int32 = 0
    private static var space: UInt64 = 0
    private static var addWindows: AddWindowsFn?
    private static var didPrepare = false

    /// Creates the overlay space once. Returns false if SkyLight is unavailable
    /// or its layout changed, in which case the caller simply skips the overlay.
    @discardableResult
    static func prepare() -> Bool {
        if didPrepare { return addWindows != nil }
        didPrepare = true

        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
            RTLD_NOW
        ) else {
            return false
        }

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }

        guard
            let mainConnectionID = symbol("SLSMainConnectionID", as: MainConnectionIDFn.self),
            let spaceCreate = symbol("SLSSpaceCreate", as: SpaceCreateFn.self),
            let setAbsoluteLevel = symbol("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevelFn.self),
            let showSpaces = symbol("SLSShowSpaces", as: ShowSpacesFn.self),
            let addWindows = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindowsFn.self)
        else {
            return false
        }

        connection = mainConnectionID()
        space = spaceCreate(connection, 1, 0)
        guard space != 0 else { return false }

        setAbsoluteLevel(connection, space, lockScreenAbsoluteLevel)
        showSpaces(connection, [space] as CFArray)

        self.addWindows = addWindows
        return true
    }

    static func add(_ window: NSWindow) {
        guard prepare(), let addWindows else { return }
        addWindows(connection, space, [window.windowNumber] as CFArray, moveSelector)
    }
}
