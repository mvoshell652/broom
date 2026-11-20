import BroomCore
import Foundation
import os
import UserNotifications

/// Posts notifications through the system and reports which action the user picked.
@MainActor
final class UserNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called with a session id when the user chooses Open, or clicks the notification.
    var onOpen: (@MainActor (String) -> Void)?
    /// Called with a session id when the user chooses Snooze 1h.
    var onSnooze: (@MainActor (String) -> Void)?

    private let log = Logger(subsystem: "app.broom", category: "notifications")

    private nonisolated static let category = "session"
    private nonisolated static let openAction = "open"
    private nonisolated static let snoozeAction = "snooze"
    private nonisolated static let sessionKey = "sessionID"

    /// Whether the system notification service can be used. It needs an app bundle: asking for it from a bare
    /// executable (`swift run`) crashes. `BROOM_NO_NOTIFICATIONS` turns it off for tests.
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && ProcessInfo.processInfo.environment["BROOM_NO_NOTIFICATIONS"] == nil
    }

    /// Registers the notification actions and asks the user for permission.
    func configure() {
        guard Self.isAvailable else {
            log.info("Notifications are off: not running from an app bundle")
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.category,
                actions: [
                    UNNotificationAction(identifier: Self.openAction, title: "Open", options: [.foreground]),
                    UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 1h"),
                ],
                intentIdentifiers: []
            ),
        ])
        Task {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                log.info("Notification permission granted: \(granted)")
            } catch {
                log.error("Could not ask for notification permission: \(error)")
            }
        }
    }

    func post(_ content: NotificationContent) {
        guard Self.isAvailable else { return }
        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.sound = .default
        notification.userInfo = [Self.sessionKey: content.sessionID]
        // Open and Snooze make sense for a waiting session; a finished one only opens.
        if content.kind == .waiting { notification.categoryIdentifier = Self.category }
        // One notification per session: a newer one replaces the older.
        let request = UNNotificationRequest(identifier: content.sessionID, content: notification, trigger: nil)
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                log.error("Could not post a notification: \(error)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Broom is a menu bar app and is never "in front", so always show the banner.
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let sessionID = response.notification.request.content.userInfo[Self.sessionKey] as? String else { return }
        await handle(actionIdentifier: response.actionIdentifier, sessionID: sessionID)
    }

    private func handle(actionIdentifier: String, sessionID: String) {
        switch actionIdentifier {
        case Self.snoozeAction: onSnooze?(sessionID)
        case Self.openAction, UNNotificationDefaultActionIdentifier: onOpen?(sessionID)
        default: break
        }
    }
}
