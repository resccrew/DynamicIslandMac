import AppKit

/// App icons by bundle id, cached so SwiftUI always gets the *same* image
/// object — `FlipArtwork` compares images by identity, and a fresh icon per
/// render would read as a new cover on every frame.
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    /// Main thread only (called from views and the model).
    static func icon(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}

/// Media and audio are often reported by a helper process rather than the app
/// itself — Safari plays through `com.apple.WebKit.GPU`, Chromium browsers
/// and Electron apps through `<app>.helper…`. Everything user-facing (icon,
/// "open", call name) wants the app.
enum AppIdentity {
    static func owner(of bundleID: String) -> String {
        if bundleID.hasPrefix("com.apple.WebKit.") { return "com.apple.Safari" }
        if let range = bundleID.range(of: ".helper") { return String(bundleID[..<range.lowerBound]) }
        return bundleID
    }
}
