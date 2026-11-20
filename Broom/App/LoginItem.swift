import Foundation
import ServiceManagement

/// Opens Broom when the user logs in (`SMAppService.mainApp`).
enum LoginItem {
    /// Whether this copy of Broom can be a login item. Only an app bundle can.
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Whether Broom is set to open at login.
    static var isEnabled: Bool {
        isAvailable && SMAppService.mainApp.status == .enabled
    }

    /// Whether the user has to allow Broom in System Settings before it can open at login.
    static var needsApproval: Bool {
        isAvailable && SMAppService.mainApp.status == .requiresApproval
    }

    /// Opens the Login Items pane of System Settings.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Turns opening at login on or off.
    static func setEnabled(_ enabled: Bool) throws {
        guard isAvailable else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
