import Foundation
import SwiftUI
import ServiceManagement
import CleanerEngine

/// What the menu bar item shows beside its icon.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    /// "182 GB free"
    case freeSpace
    /// "37% free"
    case percentage
    /// Just the disk icon.
    case iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .freeSpace: return L10n.t("menubarStyle.freeSpace", "Free space")
        case .percentage: return L10n.t("menubarStyle.percentage", "Percentage")
        case .iconOnly: return L10n.t("menubarStyle.iconOnly", "Icon only")
        }
    }

    static let defaultsKey = "menuBarStyle"

    /// The saved style. Installs from before the picker existed stored a single
    /// "show as percentage" flag; that choice carries over.
    static func stored(in defaults: UserDefaults = .standard) -> MenuBarStyle {
        if let raw = defaults.string(forKey: defaultsKey), let style = MenuBarStyle(rawValue: raw) {
            return style
        }
        return defaults.bool(forKey: "menuBarShowsPercentage") ? .percentage : .freeSpace
    }
}

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

    /// What the menu bar item shows next to its icon. `@Published` rather than
    /// `@AppStorage` because the menu bar label has to re-render the moment the
    /// picker changes (`@AppStorage` inside an ObservableObject does not publish).
    @Published var menuBarStyle: MenuBarStyle = MenuBarStyle.stored() {
        didSet { UserDefaults.standard.set(menuBarStyle.rawValue, forKey: MenuBarStyle.defaultsKey) }
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

    private init() {
        // Read the launch language before any code path can change it: the Settings
        // picker compares against this to decide whether a restart is still pending.
        _ = AppLanguage.launchLanguage
    }

    var cleanerOptions: CleanerOptions {
        CleanerOptions(
            dryRun: dryRunDefault,
            moveToTrash: moveToTrashDefault,
            logAgeThresholdDays: logAgeThresholdDays
        )
    }
}
