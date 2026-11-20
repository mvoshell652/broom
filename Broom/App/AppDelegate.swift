import AppKit

/// App-level setup. Login item and notifications arrive with later build steps.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu bar app: no Dock icon, no main menu. A bundled build also sets LSUIElement.
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
