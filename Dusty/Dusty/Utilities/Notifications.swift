import UserNotifications
import AppKit
import CleanerEngine

enum ResultBannerStyle { case reclaimed, trashed, undoable }

enum LowDiskNotifier {
    static let cleanActionID = "CLEAN_SAFE"
    static let categoryID = "LOW_DISK"

    /// Register the action category + delegate. Does NOT prompt for permission.
    static func configure(delegate: UNUserNotificationCenterDelegate) {
        let center = UNUserNotificationCenter.current()
        let action = UNNotificationAction(identifier: cleanActionID, title: "Clean Safe", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: categoryID, actions: [action], intentIdentifiers: [])
        ])
        center.delegate = delegate
    }

    static func notifyLowDisk(freeBytes: Int64) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                post(freeBytes: freeBytes)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { post(freeBytes: freeBytes) }
                }
            default:
                break // denied: respect the choice, never prompt again
            }
        }
    }

    private static func post(freeBytes: Int64) {
        let content = UNMutableNotificationContent()
        content.title = "Low disk space"
        content.body = "\(DiskSpaceMonitor.formatBytes(freeBytes)) available. Reclaim space with a Safe clean."
        content.categoryIdentifier = categoryID
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "low-disk", content: content, trigger: nil)
        )
    }
}

/// Receipt for a scheduled auto-clean: the one moment an opt-in background
/// delete must be loud about what it did.
enum AutoCleanNotifier {
    static func notify(bytesFreed: Int64) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                post(bytesFreed: bytesFreed)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { post(bytesFreed: bytesFreed) }
                }
            default:
                break // denied: respect the choice, never prompt again
            }
        }
    }

    private static func post(bytesFreed: Int64) {
        let content = UNMutableNotificationContent()
        content.title = "Auto-clean finished"
        content.body = "Dusty reclaimed \(DiskSpaceMonitor.formatBytes(bytesFreed)) of Safe-level caches. Every path is in the deletion log."
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "auto-clean-\(UUID().uuidString)", content: content, trigger: nil)
        )
    }
}

/// Retains the notification delegate and forwards the "Clean Safe" action to the view model.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()
    var onCleanSafe: (() -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == LowDiskNotifier.cleanActionID
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in self.onCleanSafe?() }
        }
        completionHandler()
    }
}
