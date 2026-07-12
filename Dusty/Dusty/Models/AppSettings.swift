import Foundation
import SwiftUI
import ServiceManagement
import CleanerEngine

/// Thin wrapper over SMAppService for the "open at login" feature.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ enabled: Bool) {
        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("refreshIntervalSeconds") var refreshIntervalSeconds: Double = 30
    @AppStorage("dryRunDefault") var dryRunDefault: Bool = false
    @AppStorage("moveToTrashDefault") var moveToTrashDefault: Bool = true
    @AppStorage("logAgeThresholdDays") var logAgeThresholdDays: Int = 30

    /// Background scanner: quietly keeps the menu bar "to clean" figure current. Never deletes.
    @AppStorage("autoScanEnabled") var autoScanEnabled: Bool = true
    @AppStorage("autoScanIntervalHours") var autoScanIntervalHours: Int = 4

    /// Scheduled auto-clean (opt-in, default OFF): a Safe-level clean on a cadence,
    /// announced with a notification. Enabling starts the period from now, so the
    /// first clean never fires the moment the toggle flips.
    @Published var autoCleanEnabled: Bool = UserDefaults.standard.bool(forKey: "autoCleanEnabled") {
        didSet {
            UserDefaults.standard.set(autoCleanEnabled, forKey: "autoCleanEnabled")
            if autoCleanEnabled && lastAutoCleanAt == nil { lastAutoCleanAt = Date() }
        }
    }
    @AppStorage("autoCleanFrequencyDays") var autoCleanFrequencyDays: Int = 7

    /// Reactive auto-clean (opt-in, default OFF): run the unattended clean the moment
    /// free space drops below the threshold instead of waiting for the calendar.
    /// `AutoCleanPolicy.reactiveCooldown` spaces out repeat attempts when a clean
    /// cannot push free space back over the line.
    @AppStorage("autoCleanWhenLowDisk") var autoCleanWhenLowDisk: Bool = false
    @AppStorage("autoCleanLowDiskThresholdGB") var autoCleanLowDiskThresholdGB: Int = 10

    /// Scope for unattended cleans: also include Developer-level caches (DerivedData,
    /// package manager caches). Off by default; a rebuild after a surprise cache wipe
    /// is a cost the user has to opt into.
    @AppStorage("autoCleanIncludesDeveloper") var autoCleanIncludesDeveloper: Bool = false

    var autoCleanLevels: [CleanupLevel] {
        autoCleanIncludesDeveloper ? [.safe, .developer] : [.safe]
    }

    var lastAutoCleanAt: Date? {
        get { UserDefaults.standard.object(forKey: "lastAutoCleanAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastAutoCleanAt") }
    }

    var lastReactiveAutoCleanAt: Date? {
        get { UserDefaults.standard.object(forKey: "lastReactiveAutoCleanAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastReactiveAutoCleanAt") }
    }

    /// Menu bar free space as "37% free" instead of "182 GB free". `@Published` rather
    /// than `@AppStorage` because the menu bar label has to re-render the moment the
    /// toggle flips (`@AppStorage` inside an ObservableObject does not publish).
    @Published var menuBarShowsPercentage: Bool = UserDefaults.standard.bool(forKey: "menuBarShowsPercentage") {
        didSet { UserDefaults.standard.set(menuBarShowsPercentage, forKey: "menuBarShowsPercentage") }
    }

    /// The "N GB to clean" suffix in the menu bar. On by default; same `@Published`
    /// pattern as above so the label re-renders the moment it flips.
    @Published var menuBarShowsReclaimable: Bool = (UserDefaults.standard.object(forKey: "menuBarShowsReclaimable") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(menuBarShowsReclaimable, forKey: "menuBarShowsReclaimable") }
    }

    /// First-run flag: the welcome overlay shows until the user starts (or skips)
    /// their first scan. `@Published` so the panel dismisses the moment it flips.
    @Published var hasSeenWelcome: Bool = UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
        didSet { UserDefaults.standard.set(hasSeenWelcome, forKey: "hasSeenWelcome") }
    }

    @Published var launchAtLogin: Bool = LoginItem.isEnabled {
        didSet { LoginItem.set(launchAtLogin) }
    }

    var cleanerOptions: CleanerOptions {
        CleanerOptions(
            dryRun: dryRunDefault,
            moveToTrash: moveToTrashDefault,
            logAgeThresholdDays: logAgeThresholdDays
        )
    }
}
