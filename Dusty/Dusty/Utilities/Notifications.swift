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
        let action = UNNotificationAction(
            identifier: cleanActionID,
            title: L10n.t("notification.action.cleanSafe", "Clean Safe"),
            options: [.foreground]
        )
        // One call registers every category: `setNotificationCategories`
        // replaces whatever was registered before.
        center.setNotificationCategories([
            UNNotificationCategory(identifier: categoryID, actions: [action], intentIdentifiers: []),
            MemoryPressureNotifier.category
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
        content.title = L10n.t("notification.lowDisk.title", "Low disk space")
        content.body = L10n.f(
            "notification.lowDisk.body",
            "%@ available. Reclaim space with a Safe clean.",
            DiskSpaceMonitor.formatBytes(freeBytes)
        )
        content.categoryIdentifier = categoryID
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "low-disk", content: content, trigger: nil)
        )
    }
}

/// Receipt for an unattended clean: the one moment an opt-in background
/// delete must be loud about what it did.
enum AutoCleanNotifier {
    static func notify(bytesFreed: Int64, trigger: AutoCleanTrigger = .scheduled) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                post(bytesFreed: bytesFreed, trigger: trigger)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { post(bytesFreed: bytesFreed, trigger: trigger) }
                }
            default:
                break // denied: respect the choice, never prompt again
            }
        }
    }

    private static func post(bytesFreed: Int64, trigger: AutoCleanTrigger) {
        let content = UNMutableNotificationContent()
        let freed = DiskSpaceMonitor.formatBytes(bytesFreed)
        switch trigger {
        case .scheduled:
            content.title = L10n.t("notification.autoClean.title", "Auto-clean finished")
            content.body = L10n.f(
                "notification.autoClean.body",
                "Dusty reclaimed %@ of cached junk. Every path is in the deletion log.",
                freed
            )
        case .lowDisk:
            content.title = L10n.t("notification.autoCleanLowDisk.title", "Disk space was running low")
            content.body = L10n.f(
                "notification.autoCleanLowDisk.body",
                "Dusty freed %@ automatically. Every path is in the deletion log.",
                freed
            )
        }
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "auto-clean-\(UUID().uuidString)", content: content, trigger: nil)
        )
    }
}

/// "Memory is running low": sent when pressure has stayed high (see
/// `MemoryAlertPolicy`), naming the apps holding the most so the fix is obvious.
enum MemoryPressureNotifier {
    static let showActionID = "SHOW_MEMORY"
    static let categoryID = "MEMORY_PRESSURE"

    static var category: UNNotificationCategory {
        let action = UNNotificationAction(
            identifier: showActionID,
            title: L10n.t("notification.action.showMemory", "Show Memory"),
            options: [.foreground]
        )
        return UNNotificationCategory(identifier: categoryID, actions: [action], intentIdentifiers: [])
    }

    static func notify(appNames: [String], bytes: Int64, critical: Bool) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                post(appNames: appNames, bytes: bytes, critical: critical)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { post(appNames: appNames, bytes: bytes, critical: critical) }
                }
            default:
                break // denied: respect the choice, never prompt again
            }
        }
    }

    private static func post(appNames: [String], bytes: Int64, critical: Bool) {
        let content = UNMutableNotificationContent()
        content.title = critical
            ? L10n.t("notification.memory.title.critical", "Your Mac is out of memory")
            : L10n.t("notification.memory.title", "Memory is running low")
        if appNames.isEmpty {
            content.body = L10n.t("notification.memory.bodyNoApps",
                                  "Quitting apps you are not using gives their memory back. Open Dusty to see which.")
        } else {
            content.body = L10n.f(
                "notification.memory.body",
                "Using the most: %1$@ (%2$@). Open Dusty to quit what you are not using.",
                appNames.formatted(.list(type: .and)),
                MemorySnapshot.formatBytes(bytes)
            )
        }
        content.categoryIdentifier = categoryID
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "memory-pressure", content: content, trigger: nil)
        )
    }
}

/// The menu bar panel, opened from code. `MenuBarExtra` has no API for it, so
/// this clicks Dusty's own status item button, found through its window. If a
/// future macOS hides that button, it quietly does nothing: the app is still
/// activated and the panel opens on the right screen at the next click.
@MainActor
enum MenuBarPanel {
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            // Give activation a moment, or the panel can open and lose focus at once.
            try? await Task.sleep(nanoseconds: 200_000_000)
            // Already open: a click would close it.
            if NSApp.windows.contains(where: { $0.isVisible && $0.className.contains("MenuBarExtra") }) { return }
            for window in NSApp.windows {
                if let button = statusBarButton(in: window.contentView) {
                    button.performClick(nil)
                    return
                }
            }
        }
    }

    private static func statusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = statusBarButton(in: subview) { return button }
        }
        return nil
    }
}

/// Retains the notification delegate and forwards the "Clean Safe" and "Show
/// Memory" actions to the view model.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()
    var onCleanSafe: (() -> Void)?
    var onShowMemory: (() -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.categoryIdentifier == MemoryPressureNotifier.categoryID {
            if response.actionIdentifier == MemoryPressureNotifier.showActionID
                || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                Task { @MainActor in self.onShowMemory?() }
            }
            completionHandler()
            return
        }
        if response.actionIdentifier == LowDiskNotifier.cleanActionID
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in self.onCleanSafe?() }
        }
        completionHandler()
    }
}
