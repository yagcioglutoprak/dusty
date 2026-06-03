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
