import ServiceManagement

/// «Открывать при входе в систему» — the system's login items are the source of
/// truth, so nothing is stored in `IslandSettings`.
enum LaunchAtLogin {
    enum State: Equatable {
        case enabled
        case disabled
        /// Registered, but the user still has to allow it in System Settings → Login Items.
        case requiresApproval
        /// Not running from an installed app bundle (e.g. `swift run`), so it can't register.
        case unavailable
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    static func set(_ enabled: Bool) -> Result<Void, Error> {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
