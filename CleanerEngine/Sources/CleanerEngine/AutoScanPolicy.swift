import Foundation

/// What woke the background scanner.
public enum AutoScanTrigger: Sendable, Equatable {
    /// The slow periodic heartbeat.
    case periodic
    /// The Mac woke from sleep.
    case wake
    /// The app just launched.
    case launch
    /// Free space dropped sharply since the last scan (caches grew).
    case freeSpaceDrop
    /// Free space crossed the low-disk threshold.
    case lowDisk

    /// The low-disk trigger is urgent: it preempts the cooldown and Low Power Mode so the
    /// menu bar figure is fresh exactly when the user is about to be nudged.
    var isUrgent: Bool { self == .lowDisk }
}

/// Pure decision for whether a background scan should run right now. Kept free of timers,
/// notifications, and app state so it can be tested directly.
public enum AutoScanPolicy {
    public static func shouldScan(
        trigger: AutoScanTrigger,
        now: Date,
        lastScanAt: Date?,
        isUserScanning: Bool,
        isCleaning: Bool,
        lowPowerMode: Bool,
        cooldown: TimeInterval = 120
    ) -> Bool {
        // Never compete with the user's own scan or an in-progress clean.
        if isUserScanning || isCleaning { return false }
        // A low-disk crossing always forces a fresh scan.
        if trigger.isUrgent { return true }
        // Otherwise be a good citizen: skip on battery saver and within the cooldown.
        if lowPowerMode { return false }
        if let last = lastScanAt, now.timeIntervalSince(last) < cooldown { return false }
        return true
    }
}
