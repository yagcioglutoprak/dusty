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

    /// Reclaimable Safe-level space found by the silent background scan. Drives the
    /// menu bar "to clean" suffix. Separate from `scanResult` so a background scan never
    /// clobbers the selections in an open panel.
    @Published var backgroundReclaimableBytes: Int64 = 0
    @Published var lastBackgroundScanAt: Date?

    /// Scan-derived observations (orphaned tool data, untouched caches) and the
    /// disk's direction of travel. Read-only pointers; nothing here selects or
    /// deletes anything.
    @Published var advisories: [Advisory] = []
    @Published var diskForecast: DiskForecast?

    private let engine = CleanerEngine()
    private let diskMonitor = DiskSpaceMonitor()
    private let diskHistory = DiskHistoryStore.shared
    private var refreshTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var undoEntries: [DeletionEntry] = []
    private var undoTask: Task<Void, Never>?
    /// Level of the clean the current undo window belongs to, so undo can rescan it.
    private var undoLevel: CleanupLevel = .safe
    /// Whether the trashed items are purged when the undo window closes (reclaiming
    /// space) or stay in the Trash because the user prefers emptying it themselves.
    private var purgeAfterUndo = true
    /// Whether the last clean was credited to the lifetime stats, so an undo only
    /// reverses a figure that was actually recorded (keep-in-Trash cleans are not).
    private var lastCleanRecordedInStats = false
    private var wasDiskLow = false

    private var autoScan: AutoScanController?
    private var isBackgroundScanning = false
    /// Free space at the last background scan, for the "free space dropped sharply" trigger.
    private var freeSpaceAtLastBackgroundScan: Int64?
    /// A background scan fires when free space falls by more than this since the last one.
    private let freeSpaceDropTriggerBytes: Int64 = 2 * 1_073_741_824

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
        autoScan = AutoScanController(viewModel: self, settings: AppSettings.shared)
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
        // Low-disk detection keys off the REAL free space, not the post-clean projected
        // floor: during the floor window `freeSpaceBytes` is optimistic and could mask a
        // genuine low-disk state (or vice versa). The displayed value can stay projected;
        // the crossing and its notification must reflect ground truth.
        let realLow = totalSpaceBytes > 0 && Double(real) / Double(totalSpaceBytes) < Self.lowDiskRatio
        if realLow && !wasDiskLow {
            LowDiskNotifier.notifyLowDisk(freeBytes: real)
            // A fresh scan at the low-disk line keeps the menu bar figure honest.
            requestBackgroundScan(trigger: .lowDisk)
        }
        wasDiskLow = realLow

        // The reactive auto-clean keys off the same ground-truth figure, every tick,
        // not just the crossing: the policy's threshold and cooldown do the gating.
        reactiveAutoCleanIfNeeded(freeBytes: real)

        // Caches grew enough to be worth re-checking: rescan off the existing sampler.
        if let baseline = freeSpaceAtLastBackgroundScan,
           baseline - freeSpaceBytes > freeSpaceDropTriggerBytes {
            requestBackgroundScan(trigger: .freeSpaceDrop)
        }

        // Feed the trend with the REAL figure, never the post-clean projected floor:
        // an optimistic sample would flatten the very slope a clean should improve.
        if diskHistory.record(freeBytes: real) {
            diskForecast = diskHistory.forecast()
        }
    }

    private func clearFreeSpaceFloor() {
        freeSpaceFloor = nil
        freeSpaceFloorExpiry = nil
    }

    // MARK: - Background scanner (silent, scan-only)

    /// Entry point for every background-scan trigger. Consults the pure policy, then runs a
    /// silent Safe-level scan that updates only the menu bar figure, never the panel selections.
    func requestBackgroundScan(trigger: AutoScanTrigger) {
        guard AppSettings.shared.autoScanEnabled, !isBackgroundScanning else { return }
        let allowed = AutoScanPolicy.shouldScan(
            trigger: trigger,
            now: Date(),
            lastScanAt: lastBackgroundScanAt,
            isUserScanning: isScanning,
            isCleaning: isCleaning,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        guard allowed else { return }
        isBackgroundScanning = true
        Task { await performBackgroundScan() }
    }

    private func performBackgroundScan() async {
        let result = await engine.scan(levels: [.safe], sizingPolicy: .cached)
        backgroundReclaimableBytes = result.levelResults[.safe]?.totalBytes ?? 0
        lastBackgroundScanAt = Date()
        freeSpaceAtLastBackgroundScan = freeSpaceBytes
        isBackgroundScanning = false
    }

    // MARK: - Scheduled auto-clean (opt-in)

    private var isAutoCleaning = false

    /// Runs the opt-in scheduled clean when its period has elapsed. Called from the
    /// same triggers as the background scanner. The pure `AutoCleanPolicy` holds the
    /// gates (busy, Low Power Mode, dry-run-by-default, period math).
    func autoCleanIfDue() {
        let settings = AppSettings.shared
        if settings.autoCleanEnabled, settings.lastAutoCleanAt == nil {
            // Enabled before this baseline existed: start the period now.
            settings.lastAutoCleanAt = Date()
            return
        }
        guard autoCleanAllowed(trigger: .scheduled, freeBytes: freeSpaceBytes) else { return }
        isAutoCleaning = true
        Task { await performAutoClean(trigger: .scheduled) }
    }

    /// The reactive path: free space dropped below the user's threshold, clean now
    /// instead of waiting for the calendar. Fed by the free-space sampler with the
    /// REAL figure (never the post-clean projected floor); the policy's cooldown
    /// keeps a disk that stays low from turning into a delete attempt per tick.
    private func reactiveAutoCleanIfNeeded(freeBytes: Int64) {
        guard autoCleanAllowed(trigger: .lowDisk, freeBytes: freeBytes) else { return }
        isAutoCleaning = true
        Task { await performAutoClean(trigger: .lowDisk) }
    }

    private func autoCleanAllowed(trigger: AutoCleanTrigger, freeBytes: Int64) -> Bool {
        let settings = AppSettings.shared
        guard settings.hasSeenWelcome else { return false }
        return AutoCleanPolicy.shouldClean(
            trigger: trigger,
            now: Date(),
            scheduleEnabled: settings.autoCleanEnabled,
            scheduleIntervalDays: settings.autoCleanFrequencyDays,
            lastScheduledCleanAt: settings.lastAutoCleanAt,
            reactiveEnabled: settings.autoCleanWhenLowDisk,
            freeBytes: freeBytes,
            reactiveThresholdBytes: Int64(settings.autoCleanLowDiskThresholdGB) * 1_073_741_824,
            lastReactiveCleanAt: settings.lastReactiveAutoCleanAt,
            isBusy: isScanning || isCleaning || isAutoCleaning,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            dryRunDefault: settings.dryRunDefault
        )
    }

    private func performAutoClean(trigger: AutoCleanTrigger) async {
        defer { isAutoCleaning = false }
        let settings = AppSettings.shared
        guard let outcome = await SafeCleanRunner.run(engine: engine, levels: settings.autoCleanLevels) else {
            // nil means a clean is already in flight (gate held): leave the clocks
            // untouched so the next trigger retries instead of losing the period.
            return
        }
        // The clean ran (whether or not it found anything), so its clock is satisfied:
        // stamp now. Each trigger stamps only its own clock; a reactive clean must not
        // silently push the scheduled one out by a full period, or vice versa.
        switch trigger {
        case .scheduled: settings.lastAutoCleanAt = Date()
        case .lowDisk: settings.lastReactiveAutoCleanAt = Date()
        }
        refreshFreeSpace()
        if outcome.bytesFreed > 0 {
            AutoCleanNotifier.notify(bytesFreed: outcome.bytesFreed, trigger: trigger)
        }
        // Keep the menu bar figure and an open panel honest after the clean.
        backgroundReclaimableBytes = 0
        lastBackgroundScanAt = Date()
        freeSpaceAtLastBackgroundScan = freeSpaceBytes
        if scanResult != nil {
            for level in settings.autoCleanLevels {
                await rescan(level: level, settings: settings)
            }
        }
    }

    /// Formatted reclaimable space for the menu bar, or nil when there is nothing worth
    /// showing yet (no scan completed, or under 1 GB) so the label never reads "0 GB to clean".
    var menuBarReclaimableSuffix: String? {
        guard lastBackgroundScanAt != nil, backgroundReclaimableBytes >= 1_073_741_824 else { return nil }
        return DiskSpaceMonitor.formatBytes(backgroundReclaimableBytes)
    }

    /// A scan result older than this is refreshed automatically when the panel opens.
    private static let scanStaleAfter: TimeInterval = 3600

    func scanIfNeeded(settings: AppSettings) {
        guard !isScanning, !isCleaning else { return }
        guard let scannedAt = scanResult?.scannedAt else {
            startScan(settings: settings)
            return
        }
        // The app runs for weeks; without this, the panel keeps showing whatever the
        // first open found. Cached sizing makes the refresh near-instant when the
        // cache directories haven't changed.
        if Date().timeIntervalSince(scannedAt) > Self.scanStaleAfter {
            startScan(settings: settings, sizingPolicy: .cached)
        }
    }

    func startScan(settings: AppSettings, sizingPolicy: SizeCachePolicy = .fresh) {
        scanTask?.cancel()
        scanTask = Task { await scan(settings: settings, sizingPolicy: sizingPolicy) }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
        scanProgress = nil
    }

    func scan(settings: AppSettings, clearResult: Bool = true, sizingPolicy: SizeCachePolicy = .fresh) async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        if clearResult { lastDeletionResult = nil }
        scanProgress = ScanProgress(completed: 0, total: CleanupTargetRegistry.all.count, currentTargetName: "Starting…")

        let result = await engine.scan(options: settings.cleanerOptions, sizingPolicy: sizingPolicy) { [weak self] progress in
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
        refreshAdvisories(for: result)
    }

    /// Advisories walk parts of the scanned trees to double-check staleness, so
    /// they run off the main actor and land whenever they land.
    private func refreshAdvisories(for result: FullScanResult) {
        diskForecast = diskHistory.forecast()
        Task { [weak self] in
            let found = await Task.detached(priority: .utility) {
                SmartAdvisor().advisories(for: result)
            }.value
            // A newer scan may have finished meanwhile; only publish for the current one.
            guard let self, self.scanResult?.scannedAt == result.scannedAt else { return }
            self.advisories = found
        }
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
        // Hold the process-wide gate so a Shortcuts action or scheduled auto-clean
        // cannot delete the same targets underneath this clean.
        guard CleanCoordinator.shared.beginClean() else {
            errorMessage = "A clean is already in progress. Try again in a moment."
            return
        }
        defer { CleanCoordinator.shared.endClean() }
        finalizeUndo()
        isCleaning = true
        cleaningLevel = level
        errorMessage = nil

        var options = settings.cleanerOptions
        options.cleanupLevel = level
        let undoable = !options.dryRun
        options.trashForUndo = undoable
        // Developer/Deep items stay in the Trash after the undo window when the user
        // prefers emptying it themselves; everything else purges to reclaim space.
        let keepInTrashAfterUndo = level != .safe && settings.moveToTrashDefault

        let result = await engine.delete(paths: paths, targets: levelResult.targetResults.map(\.target), options: options)
        lastDeletionResult = result

        // Instant feedback: project the reclaimed space the moment a clean actually
        // frees disk (direct delete, or items that auto-purge from Trash after the
        // undo window). Cleans whose items stay in the Trash don't free space until
        // the Trash is emptied, so those just re-read the real figure.
        let willReclaim = !options.dryRun && result.bytesFreed > 0 && !keepInTrashAfterUndo
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

        // Only credit lifetime stats when this clean actually reclaims space now.
        // "Keep in Trash" cleans (Developer/Deep) do not free disk until the user
        // empties the Trash, which Dusty never observes, so crediting them would
        // overstate the lifetime total. `willReclaim` is the same gate the projected
        // free-space bump uses, keeping the receipt and the stat consistent.
        if willReclaim {
            CleanStatsStore.shared.record(level: level, bytes: result.bytesFreed, items: result.entries.count)
        }
        lastCleanRecordedInStats = willReclaim

        // Only items actually parked in the Trash can be undone or later purged.
        // Permanent deletes (e.g. Empty Trash, which bypasses the Trash) are already gone.
        let restorable = result.entries.filter { $0.trashedPath != nil }
        let anyTrashed = result.entries.contains { $0.movedToTrash }
        if undoable && !restorable.isEmpty {
            undoEntries = restorable
            undoLevel = level
            purgeAfterUndo = !keepInTrashAfterUndo
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

    /// Restore the just-trashed items of the last clean to their original locations.
    func undoLastDeletion() {
        undoTask?.cancel()
        guard !undoEntries.isEmpty else { canUndo = false; return }
        let entries = undoEntries
        let level = undoLevel
        undoEntries = []
        canUndo = false
        // The space comes back, so the lifetime stat must give it back too, but only
        // if this clean was actually credited (keep-in-Trash cleans never were).
        if lastCleanRecordedInStats, let undone = lastDeletionResult?.bytesFreed {
            CleanStatsStore.shared.unrecordLast(bytes: undone)
        }
        lastCleanRecordedInStats = false
        lastDeletionResult = nil
        clearFreeSpaceFloor()
        let engine = self.engine
        Task {
            let result = await Task.detached { engine.restore(entries) }.value
            if !result.failures.isEmpty {
                self.errorMessage = "Restored \(result.restoredCount) of \(entries.count) items. Some could not be moved back (the original location may be occupied)."
            }
            self.refreshFreeSpace()
            await self.rescan(level: level, settings: AppSettings.shared)
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

    /// Close the undo window: purge the trashed items to reclaim space, or leave them
    /// in the Trash when the user prefers emptying it themselves (Developer/Deep with
    /// the Trash preference on).
    private func finalizeUndo() {
        undoTask?.cancel()
        guard canUndo, !undoEntries.isEmpty else { canUndo = false; return }
        let entries = undoEntries
        undoEntries = []
        canUndo = false
        guard purgeAfterUndo else {
            bannerStyle = .trashed
            return
        }
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

    /// "37% free" variant of the menu bar label. Falls back to the byte form until
    /// the total volume size is known (first refresh hasn't completed yet).
    var menuBarPercentLabel: String {
        guard totalSpaceBytes > 0 else { return menuBarLabel }
        return "\(Int((freeSpaceRatio * 100).rounded()))% free"
    }

    var freeSpaceRatio: Double {
        guard totalSpaceBytes > 0 else { return 0 }
        return Double(freeSpaceBytes) / Double(totalSpaceBytes)
    }

    /// Fraction of the volume below which the disk is treated as low.
    private static let lowDiskRatio = 0.15
    var isDiskLow: Bool { freeSpaceRatio < Self.lowDiskRatio }

    private func mutateScanResult(level: CleanupLevel, _ mutate: (inout LevelScanResult) -> Void) {
        guard var scan = scanResult, var levelResult = scan.levelResults[level] else { return }
        mutate(&levelResult)
        scan.levelResults[level] = LevelScanResult(level: level, targetResults: levelResult.targetResults)
        scanResult = scan
    }
}
