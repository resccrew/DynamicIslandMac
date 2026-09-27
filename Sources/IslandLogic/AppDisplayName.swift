import Foundation

/// A readable app name for a bundle identifier, for places where the app may
/// not be installed (a call app seen only through its microphone use).
public enum AppDisplayName {
    /// Names of the apps the island recognises as calling apps and browsers.
    public static let known: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Teams",
        "com.microsoft.teams": "Teams",
        "com.hnc.Discord": "Discord",
        "ru.keepcoder.Telegram": "Telegram",
        "org.telegram.desktop": "Telegram",
        "com.apple.FaceTime": "FaceTime",
        "net.whatsapp.WhatsApp": "WhatsApp",
        "desktop.WhatsApp": "WhatsApp",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.skype.skype": "Skype",
        "com.viber.osx": "Viber",
        "org.whispersystems.signal-desktop": "Signal",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.google.Chrome": "Chrome",
        "company.thebrowser.Browser": "Arc",
        "com.brave.Browser": "Brave",
        "com.microsoft.edgemac": "Edge",
        "ru.yandex.desktop.yandex-browser": "Яндекс Браузер",
        "com.operasoftware.Opera": "Opera",
        "org.mozilla.firefox": "Firefox",
        "com.apple.Safari": "Safari",
    ]

    /// Trailing components that name a platform or a role, not the app.
    private static let generic: Set<String> = [
        "xos", "osx", "mac", "macos", "macgap", "desktop", "app", "client",
        "helper", "gui", "electron", "browser", "main", "gpu", "renderer",
    ]

    /// The system's name for the app when it is installed (`localized`), else
    /// the table above, else the last meaningful bundle-id component, capitalised.
    public static func resolve(bundleID: String, localized: String?) -> String {
        if let name = localized?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            return name
        }
        if let name = known[bundleID] { return name }
        return fallback(bundleID)
    }

    static func fallback(_ bundleID: String) -> String {
        let parts = bundleID.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        let meaningful = parts.dropFirst().last { !generic.contains($0.lowercased()) }
            ?? parts.last { !generic.contains($0.lowercased()) }
            ?? parts.last
            ?? bundleID
        return meaningful.prefix(1).uppercased() + meaningful.dropFirst()
    }
}
