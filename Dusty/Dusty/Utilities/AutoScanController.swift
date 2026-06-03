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
    private var wakeObserver: NSObjectProtocol?

    init(viewModel: DustyViewModel, settings: AppSettings) {
        self.viewModel = viewModel
        self.settings = settings
        start()
    }

    deinit {
        periodicTask?.cancel()
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
            Task { @MainActor in self?.viewModel?.requestBackgroundScan(trigger: .wake) }
        }

        startPeriodic()
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
            }
        }
    }
}
