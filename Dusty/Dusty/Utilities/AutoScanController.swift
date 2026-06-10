import Foundation
import AppKit
import CleanerEngine

/// Drives the background scanner's time- and system-event triggers: a slow periodic
/// heartbeat, wake-from-sleep, and a scan shortly after launch. The disk-state triggers
/// (low-disk crossing, sharp free-space drop) are detected by the view model's free-space
/// sampler. Everything funnels through `viewModel.requestBackgroundScan(trigger:)`, which
/// applies the scan policy (cooldown, Low Power Mode, not-while-busy).
@MainActor
final class AutoScanController {
    private weak var viewModel: DustyViewModel?
    private let settings: AppSettings
    private var periodicTask: Task<Void, Never>?
    private var autoCleanTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init(viewModel: DustyViewModel, settings: AppSettings) {
        self.viewModel = viewModel
        self.settings = settings
        start()
    }

    deinit {
        periodicTask?.cancel()
        autoCleanTask?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func start() {
        // Populate the menu bar figure shortly after launch.
        viewModel?.requestBackgroundScan(trigger: .launch)

        // Rescan when the Mac wakes from sleep (catches the "left it overnight" case).
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.requestBackgroundScan(trigger: .wake)
                self?.viewModel?.autoCleanIfDue()
            }
        }

        startPeriodic()
        startAutoCleanHeartbeat()
    }

    private func startPeriodic() {
        periodicTask?.cancel()
        periodicTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // Read the interval each cycle so a settings change applies without a restart.
                let hours = max(1, self?.settings.autoScanIntervalHours ?? 4)
                try? await Task.sleep(nanoseconds: UInt64(Double(hours) * 3600 * 1_000_000_000))
                guard !Task.isCancelled else { break }
                self?.viewModel?.requestBackgroundScan(trigger: .periodic)
                self?.viewModel?.autoCleanIfDue()
            }
        }
    }

    /// The scan heartbeat can be hours apart, and an auto-clean whose period lapsed
    /// while the Mac was off should not wait half a day for the next scan tick. An
    /// hourly due-check is free: `autoCleanIfDue` refuses unless the period elapsed.
    private func startAutoCleanHeartbeat() {
        autoCleanTask?.cancel()
        autoCleanTask = Task { @MainActor [weak self] in
            // A few minutes after launch, then hourly.
            try? await Task.sleep(nanoseconds: 180 * 1_000_000_000)
            while !Task.isCancelled {
                self?.viewModel?.autoCleanIfDue()
                try? await Task.sleep(nanoseconds: 3600 * 1_000_000_000)
            }
        }
    }
}
