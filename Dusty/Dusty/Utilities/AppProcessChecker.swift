import AppKit

enum AppProcessChecker {
    /// True if an app with the given bundle id (preferred) or exact localized name is running.
    static func isRunning(name: String?, bundleID: String?) -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        if let id = bundleID, apps.contains(where: { $0.bundleIdentifier == id }) { return true }
        if let name {
            return apps.contains { $0.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame }
        }
        return false
    }
}
