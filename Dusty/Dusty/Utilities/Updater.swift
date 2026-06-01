import Foundation
import Combine
import Sparkle

/// SwiftUI-friendly wrapper over Sparkle's updater.
///
/// The feed URL and the EdDSA public key that pins update signatures live in `Info.plist`
/// (`SUFeedURL`, `SUPublicEDKey`). On first launch Dusty opts into automatic checks and
/// automatic install so the app keeps itself current; the user can turn either off in
/// Settings. The private signing key never ships in the app: it lives only in the
/// release machine's login keychain (see `docs/UPDATES.md`).
@MainActor
final class Updater: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// Mirrors Sparkle's readiness so the "Check for Updates" button can disable itself
    /// while a check is already in flight.
    @Published private(set) var canCheckForUpdates = false

    private static let defaultsAppliedKey = "DustyUpdaterDefaultsApplied"

    init() {
        // `startingUpdater: true` begins the scheduled background checks right away.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Default to fully automatic updates on first run, then leave the choice to the
        // user. We only seed the defaults once so a later opt-out is never overwritten.
        if !UserDefaults.standard.bool(forKey: Self.defaultsAppliedKey) {
            controller.updater.automaticallyChecksForUpdates = true
            controller.updater.automaticallyDownloadsUpdates = true
            UserDefaults.standard.set(true, forKey: Self.defaultsAppliedKey)
        }

        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// User-initiated check that shows Sparkle's progress and "you're up to date" UI.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }
}

extension Bundle {
    /// Marketing version, e.g. "1.0.0" (`CFBundleShortVersionString`).
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    /// Build number, e.g. "1" (`CFBundleVersion`). Sparkle compares this across versions.
    var buildVersion: String {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}
