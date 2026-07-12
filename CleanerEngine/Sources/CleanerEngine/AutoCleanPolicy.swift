import Foundation

/// What asked for an unattended clean.
public enum AutoCleanTrigger: Sendable, Equatable {
    /// The scheduled cadence (every N days) came due.
    case scheduled
    /// Free space dropped below the user's low-disk threshold.
    case lowDisk
}

/// Pure decision for whether an unattended clean should run right now. Kept free of
/// timers, UserDefaults, and app state so every rule is testable directly, the same
/// way `AutoScanPolicy` guards the background scanner.
///
/// Unlike a background scan, an unattended clean deletes files, so nothing here is
/// urgent enough to preempt the shared gates: never while the user is mid-scan or
/// mid-clean, never in Low Power Mode (deleting on battery saver is not the favor it
/// sounds like), and never while dry-run-by-default is on (that user asked for nothing
/// to be deleted unattended).
public enum AutoCleanPolicy {
    /// Reactive cleans get a long cooldown of their own. If a clean could not push
    /// free space back above the threshold, the disk stays "low" on every sampler
    /// tick; without the cooldown that would mean a delete attempt every few seconds.
    public static let reactiveCooldown: TimeInterval = 6 * 3600

    public static func shouldClean(
        trigger: AutoCleanTrigger,
        now: Date,
        scheduleEnabled: Bool,
        scheduleIntervalDays: Int,
        lastScheduledCleanAt: Date?,
        reactiveEnabled: Bool,
        freeBytes: Int64,
        reactiveThresholdBytes: Int64,
        lastReactiveCleanAt: Date?,
        reactiveCooldown: TimeInterval = AutoCleanPolicy.reactiveCooldown,
        isBusy: Bool,
        lowPowerMode: Bool,
        dryRunDefault: Bool
    ) -> Bool {
        if isBusy || lowPowerMode || dryRunDefault { return false }
        switch trigger {
        case .scheduled:
            guard scheduleEnabled else { return false }
            // No baseline yet means the toggle just flipped: the caller stamps the
            // baseline and the first clean waits a full period, never firing the
            // moment the setting is enabled.
            guard let last = lastScheduledCleanAt else { return false }
            let interval = TimeInterval(max(1, scheduleIntervalDays)) * 86_400
            return now.timeIntervalSince(last) >= interval
        case .lowDisk:
            guard reactiveEnabled else { return false }
            guard reactiveThresholdBytes > 0, freeBytes < reactiveThresholdBytes else { return false }
            if let last = lastReactiveCleanAt, now.timeIntervalSince(last) < reactiveCooldown {
                return false
            }
            return true
        }
    }
}
