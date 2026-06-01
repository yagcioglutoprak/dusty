import Foundation
import AppKit
import UserNotifications
import CleanerEngine

@MainActor
final class DustyViewModel: ObservableObject {
    @Published var freeSpaceBytes: Int64 = 0
    @Published var totalSpaceBytes: Int64 = 0
    @Published var scanResult: FullScanResult?
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var cleaningLevel: CleanupLevel?
    @Published var lastDeletionResult: DeletionResult?
    @Published var errorMessage: String?
    @Published var showSettings = false
    @Published var pendingConfirmationLevel: CleanupLevel?
    @Published var expandedLevels: Set<CleanupLevel> = [.safe]
    @Published var scanProgress: ScanProgress?
    @Published var hasScannedOnce = false
    @Published var canUndo = false
    @Published var bannerStyle: ResultBannerStyle = .reclaimed

    private let engine = CleanerEngine()
    private let diskMonitor = DiskSpaceMonitor()
    private var refreshTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var undoEntries: [DeletionEntry] = []
    private var undoTask: Task<Void, Never>?
    private var wasDiskLow = false

    /// After a clean, macOS's "available" figure lags the real deletion by
    /// seconds (and Safe items sit briefly in the Trash before being purged).
    /// We project the reclaimed space immediately and hold this floor so the
    /// laggy OS value can't snap the number back down before it catches up.
    private var freeSpaceFloor: Int64?
    private var freeSpaceFloorExpiry: Date?

    init() {
        refreshFreeSpace()
        startAutoRefresh(interval: AppSettings.shared.refreshIntervalSeconds)
        LowDiskNotifier.configure(delegate: NotificationCoordinator.shared)
        NotificationCoordinator.shared.onCleanSafe = { [weak self] in self?.handleCleanSafeFromNotification() }
    }

    func startAutoRefresh(interval: TimeInterval) {
        refreshTask?.cancel()
        refreshFreeSpace()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                refreshFreeSpace()
            }
        }
    }

    func refreshFreeSpace() {
        let real = diskMonitor.freeSpaceBytes()
        if let floor = freeSpaceFloor, let expiry = freeSpaceFloorExpiry, real < floor, Date() < expiry {
            // OS hasn't caught up to the reclaim yet: hold the projected value.
            freeSpaceBytes = floor
        } else {
            freeSpaceFloor = nil
            freeSpaceFloorExpiry = nil
            freeSpaceBytes = real
        }
        totalSpaceBytes = diskMonitor.totalSpaceBytes()
        let low = isDiskLow
        if low && !wasDiskLow { LowDiskNotifier.notifyLowDisk(freeBytes: freeSpaceBytes) }
        wasDiskLow = low
    }

    private func clearFreeSpaceFloor() {
        freeSpaceFloor = nil
        freeSpaceFloorExpiry = nil
    }

    func scanIfNeeded(settings: AppSettings) {
        if scanResult == nil && !isScanning { startScan(settings: settings) }
    }

    func startScan(settings: AppSettings) {
        scanTask?.cancel()
        scanTask = Task { await scan(settings: settings) }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
        scanProgress = nil
    }

    func scan(settings: AppSettings, clearResult: Bool = true) async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        if clearResult { lastDeletionResult = nil }
        scanProgress = ScanProgress(completed: 0, total: CleanupTargetRegistry.all.count, currentTargetName: "Starting…")

        let result = await engine.scan(options: settings.cleanerOptions) { [weak self] progress in
            Task { @MainActor in
                guard self?.isScanning == true else { return }
                self?.scanProgress = progress
            }
        }

        guard !Task.isCancelled else {
            isScanning = false
            scanProgress = nil
            return
        }
        scanResult = result
        hasScannedOnce = true
        isScanning = false
        scanProgress = nil
    }

    func requestClean(level: CleanupLevel) {
        guard !cleanablePaths(for: level).isEmpty else {
            let blocking = blockingApps(for: level)
            errorMessage = blocking.isEmpty
                ? "Select at least one item to clean."
                : "Quit \(blocking.joined(separator: ", ")) to clean their caches."
            return
        }
        pendingConfirmationLevel = level
    }

    func confirmClean(level: CleanupLevel, settings: AppSettings) async {
        let paths = cleanablePaths(for: level)
        guard let levelResult = scanResult?.levelResults[level], !paths.isEmpty else {
            pendingConfirmationLevel = nil
            return
        }
        pendingConfirmationLevel = nil
        finalizeUndo()
        isCleaning = true
        cleaningLevel = level
        errorMessage = nil

        var options = settings.cleanerOptions
        options.cleanupLevel = level
        let undoable = level == .safe && !options.dryRun
        options.trashSafeForUndo = undoable

        let result = await engine.delete(paths: paths, targets: levelResult.targetResults.map(\.target), options: options)
        lastDeletionResult = result

        // Instant feedback: project the reclaimed space the moment a clean
        // actually frees disk (direct delete, or Safe items that auto-purge from
        // Trash). Trash-only cleans (levels 2 & 3) don't free space until the
        // Trash is emptied, so those just re-read the real figure.
        let willReclaim = !options.dryRun && result.bytesFreed > 0 && (undoable || !options.effectiveMoveToTrash)
        if willReclaim {
            let projected = freeSpaceBytes + result.bytesFreed
            freeSpaceFloor = projected
            freeSpaceFloorExpiry = Date().addingTimeInterval(20)
            freeSpaceBytes = projected
        } else {
            refreshFreeSpace()
        }
        isCleaning = false
        cleaningLevel = nil

        if !result.skippedPaths.isEmpty && result.entries.isEmpty {
            errorMessage = "Cleanup failed: check permissions or try again."
        }

        // Only items actually parked in the Trash can be undone or later purged.
        // Permanent deletes (e.g. Empty Trash, which bypasses the Trash) are already gone.
        let restorable = result.entries.filter { $0.trashedPath != nil }
        let anyTrashed = result.entries.contains { $0.movedToTrash }
        if undoable && !restorable.isEmpty {
            undoEntries = restorable
            canUndo = true
            bannerStyle = .undoable
            scheduleUndoPurge()
        } else {
            canUndo = false
            // Reflect what actually happened: if nothing went to the Trash, the space is
            // already reclaimed even on a Safe-undo run that only emptied the Trash.
            bannerStyle = anyTrashed ? .trashed : .reclaimed
        }

        await rescan(level: level, settings: settings)
    }

    /// Restore the just-trashed Safe items to their original locations.
    func undoLastDeletion() {
        undoTask?.cancel()
        guard !undoEntries.isEmpty else { canUndo = false; return }
        let entries = undoEntries
        undoEntries = []
        canUndo = false
        lastDeletionResult = nil
        clearFreeSpaceFloor()
        let engine = self.engine
        Task {
            let restored = await Task.detached { engine.restore(entries) }.value
            if restored < entries.count {
                self.errorMessage = "Restored \(restored) of \(entries.count) items. Some could not be moved back (the original location may be occupied)."
            }
            self.refreshFreeSpace()
            await self.rescan(level: .safe, settings: AppSettings.shared)
        }
    }

    private func scheduleUndoPurge() {
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finalizeUndo()
        }
    }

    /// Permanently purge the trashed items once the undo window closes, reclaiming space.
    private func finalizeUndo() {
        undoTask?.cancel()
        guard canUndo, !undoEntries.isEmpty else { canUndo = false; return }
        let entries = undoEntries
        undoEntries = []
        canUndo = false
        bannerStyle = .reclaimed
        let engine = self.engine
        Task {
            _ = await Task.detached { engine.purge(entries) }.value
            // The trashed items only leave disk now, after the undo window. Re-measure so
            // the "reclaimed" receipt shows the real before -> after, not the pre-purge value
            // (which was sampled while the items still sat in the Trash).
            if let prev = self.lastDeletionResult {
                self.lastDeletionResult = DeletionResult(
                    entries: prev.entries,
                    bytesFreed: prev.bytesFreed,
                    skippedPaths: prev.skippedPaths,
                    freeSpaceBefore: prev.freeSpaceBefore,
                    freeSpaceAfter: self.diskMonitor.availableCapacityBytes()
                )
            }
            self.refreshFreeSpace()
        }
    }

    func handleCleanSafeFromNotification() {
        NSApp.activate(ignoringOtherApps: true)
        Task {
            if scanResult == nil { await scan(settings: AppSettings.shared) }
            requestClean(level: .safe)
        }
    }

    /// Refresh just one level's results in place (cheaper than a full rescan).
    private func rescan(level: CleanupLevel, settings: AppSettings) async {
        let result = await engine.scan(levels: [level], options: settings.cleanerOptions)
        guard var scan = scanResult, let updated = result.levelResults[level] else { return }
        scan.levelResults[level] = updated
        scanResult = FullScanResult(levelResults: scan.levelResults)
    }

    func cancelConfirmation() {
        pendingConfirmationLevel = nil
    }

    func togglePathSelection(level: CleanupLevel, targetID: String, pathID: String) {
        mutateScanResult(level: level) { levelResult in
            guard let ti = levelResult.targetResults.firstIndex(where: { $0.id == targetID }),
                  let pi = levelResult.targetResults[ti].resolvedPaths.firstIndex(where: { $0.id == pathID })
            else { return }
            levelResult.targetResults[ti].resolvedPaths[pi].isSelected.toggle()
        }
    }

    func setAllSelected(level: CleanupLevel, targetID: String, selected: Bool) {
        mutateScanResult(level: level) { levelResult in
            guard let ti = levelResult.targetResults.firstIndex(where: { $0.id == targetID }) else { return }
            for i in levelResult.targetResults[ti].resolvedPaths.indices {
                levelResult.targetResults[ti].resolvedPaths[i].isSelected = selected
            }
        }
    }

    func selectedLevelBytes(_ level: CleanupLevel) -> Int64 {
        scanResult?.levelResults[level]?.selectedBytes ?? 0
    }

    // MARK: - Reclaimable summary

    /// Total bytes found across every level (what the user could reclaim).
    var totalReclaimableBytes: Int64 { scanResult?.totalBytes ?? 0 }

    func reclaimableBytes(for level: CleanupLevel) -> Int64 {
        scanResult?.levelResults[level]?.totalBytes ?? 0
    }

    var hasReclaimableSpace: Bool { totalReclaimableBytes > 0 }

    /// One-tap: clean every safe item (all auto-selected) after confirmation.
    func cleanSafe() { requestClean(level: .safe) }

    func levelResult(for level: CleanupLevel) -> LevelScanResult? {
        scanResult?.levelResults[level]
    }

    func blockingApps(for level: CleanupLevel) -> [String] {
        guard let result = scanResult?.levelResults[level] else { return [] }
        let blocked = blockedTargetIDs(for: level)
        let names = result.targetResults
            .filter { blocked.contains($0.id) && $0.resolvedPaths.contains(where: \.isSelected) }
            .compactMap { $0.target.requiresAppClosed }
        return Array(Set(names)).sorted()
    }

    func canClean(level: CleanupLevel) -> Bool {
        !cleanablePaths(for: level).isEmpty
    }

    /// Target IDs whose required app is currently open: these are skipped, not blocked.
    func blockedTargetIDs(for level: CleanupLevel) -> Set<String> {
        guard let result = scanResult?.levelResults[level] else { return [] }
        return Set(result.targetResults.compactMap { tr in
            let t = tr.target
            guard t.requiresAppClosed != nil || t.requiresAppBundleID != nil,
                  AppProcessChecker.isRunning(name: t.requiresAppClosed, bundleID: t.requiresAppBundleID)
            else { return nil }
            return tr.id
        })
    }

    /// Selected paths excluding those whose app is open.
    func cleanablePaths(for level: CleanupLevel) -> [ResolvedPath] {
        guard let result = scanResult?.levelResults[level] else { return [] }
        let blocked = blockedTargetIDs(for: level)
        return result.selectedPaths.filter { !blocked.contains($0.targetID) }
    }

    func cleanableBytes(for level: CleanupLevel) -> Int64 {
        cleanablePaths(for: level).reduce(0) { $0 + $1.estimatedBytes }
    }

    func hasPermissionIssues(for level: CleanupLevel) -> Bool {
        scanResult?.levelResults[level]?.hasPermissionErrors ?? false
    }

    func openDeletionLog() {
        NSWorkspace.shared.open(engine.logFileURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: engine.logFileURL.path) {
            NSWorkspace.shared.open(engine.logFileURL)
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    var menuBarLabel: String {
        DiskSpaceMonitor.formatFreeSpaceCompact(freeSpaceBytes)
    }

    var freeSpaceRatio: Double {
        guard totalSpaceBytes > 0 else { return 0 }
        return Double(freeSpaceBytes) / Double(totalSpaceBytes)
    }

    var isDiskLow: Bool { freeSpaceRatio < 0.15 }

    private func mutateScanResult(level: CleanupLevel, _ mutate: (inout LevelScanResult) -> Void) {
        guard var scan = scanResult, var levelResult = scan.levelResults[level] else { return }
        mutate(&levelResult)
        scan.levelResults[level] = LevelScanResult(level: level, targetResults: levelResult.targetResults)
        scanResult = scan
    }
}
