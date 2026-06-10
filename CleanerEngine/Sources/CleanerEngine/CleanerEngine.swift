import Foundation

/// Pure cleanup engine: no SwiftUI dependencies. Fully unit-testable.
///
/// `@unchecked Sendable`: every stored dependency is immutable (`let`) and itself thread-safe.
/// The only reference type reachable is `FileManager`, used solely for delegate-free, concurrency-safe
/// queries (existence checks, attributes, enumeration), so the engine is safe to share across scan tasks.
public final class CleanerEngine: @unchecked Sendable {
    private let fileManager: FileManager
    private let validator: SafetyValidator
    private let sizeCalculator: SizeCalculator
    private let diskMonitor: DiskSpaceMonitor
    private let deletionLog: DeletionLogStore
    private let homeDirectory: URL

    /// Cap on concurrent directory walks during a scan, so a background scan stays a
    /// good citizen on the disk instead of starting one walk per target at once.
    private let maxConcurrentScans = 4

    public init(
        fileManager: FileManager = .default,
        validator: SafetyValidator? = nil,
        sizeCalculator: SizeCalculator? = nil,
        diskMonitor: DiskSpaceMonitor? = nil,
        deletionLog: DeletionLogStore? = nil,
        homeDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        self.validator = validator ?? SafetyValidator(fileManager: fileManager)
        // The default calculator carries a size cache so `.cached` background scans
        // can skip re-walking unchanged directories. Injected calculators decide for themselves.
        self.sizeCalculator = sizeCalculator ?? SizeCalculator(fileManager: fileManager, cache: SizeCache())
        self.diskMonitor = diskMonitor ?? DiskSpaceMonitor(fileManager: fileManager)
        self.deletionLog = deletionLog ?? FileDeletionLogStore(fileManager: fileManager)
    }

    public var logFileURL: URL { deletionLog.logFileURL }

    // MARK: - Scan

    public func scan(
        levels: Set<CleanupLevel> = Set(CleanupLevel.allCases),
        options: CleanerOptions = CleanerOptions(),
        sizingPolicy: SizeCachePolicy = .fresh,
        progress: ScanProgressHandler? = nil
    ) async -> FullScanResult {
        let targets = CleanupLevel.allCases
            .filter { levels.contains($0) }
            .flatMap { CleanupTargetRegistry.targets(for: $0) }

        let total = targets.count
        let counter = ScanProgressCounter()

        // Bounded concurrency keeps a background scan from starting a directory walk
        // per target all at once. Progress is reported as each target finishes.
        let scanned = await runBounded(targets, maxConcurrent: maxConcurrentScans) { [self] target in
            let result = await self.scanTarget(target, options: options, sizingPolicy: sizingPolicy)
            if let progress {
                let done = await counter.increment()
                progress(ScanProgress(completed: done, total: total, currentTargetName: target.displayName))
            }
            return (target.id, result)
        }

        var resultsByTargetID: [String: TargetScanResult] = [:]
        for (id, result) in scanned { resultsByTargetID[id] = result }

        var levelResults: [CleanupLevel: LevelScanResult] = [:]
        for level in CleanupLevel.allCases where levels.contains(level) {
            let levelTargets = CleanupTargetRegistry.targets(for: level)
            let targetResults = levelTargets.compactMap { resultsByTargetID[$0.id] }
            levelResults[level] = LevelScanResult(level: level, targetResults: targetResults)
        }

        return FullScanResult(levelResults: levelResults)
    }

    public func scanTarget(
        _ target: CleanupTarget,
        options: CleanerOptions,
        sizingPolicy: SizeCachePolicy = .fresh
    ) async -> TargetScanResult {
        scanTargetSync(target, options: options, sizingPolicy: sizingPolicy)
    }

    private func scanTargetSync(
        _ target: CleanupTarget,
        options: CleanerOptions,
        sizingPolicy: SizeCachePolicy
    ) -> TargetScanResult {
        if Task.isCancelled { return TargetScanResult(target: target, resolvedPaths: []) }
        var scanErrors: [String] = []
        var resolvedPaths: [ResolvedPath] = []

        if target.action == .simctlDeleteUnavailable {
            let udids = SimulatorHelper.unavailableDeviceUDIDs()
            let base = validator.expandPath("~/Library/Developer/CoreSimulator/Devices")
            let bytes = udids.reduce(Int64(0)) { sum, udid in
                sum + sizeCalculator.allocatedSize(at: (base as NSString).appendingPathComponent(udid), policy: sizingPolicy)
            }
            let count = udids.count
            let label = count > 0
                ? "Unavailable simulators (\(count) device\(count == 1 ? "" : "s"))"
                : "Unavailable simulators (none found)"
            resolvedPaths.append(ResolvedPath(
                path: "simctl:delete unavailable",
                displayName: label,
                targetID: target.id,
                estimatedBytes: bytes,
                isSelected: count > 0
            ))
            return TargetScanResult(target: target, resolvedPaths: resolvedPaths, scanErrors: scanErrors)
        }

        if target.action == .dockerPrune {
            if validator.resolveAllowlistedPaths(for: target).isEmpty {
                return TargetScanResult(target: target, resolvedPaths: [], scanErrors: ["Docker not installed"])
            }
            let bytes = estimateDockerReclaimable()
            resolvedPaths.append(ResolvedPath(
                path: "docker:system prune",
                displayName: "All unused images, build cache & stopped containers",
                targetID: target.id,
                estimatedBytes: bytes,
                isSelected: false
            ))
            return TargetScanResult(target: target, resolvedPaths: resolvedPaths)
        }

        if target.action == .simctlDeleteDevice {
            let base = validator.expandPath("~/Library/Developer/CoreSimulator/Devices")
            let devices = SimulatorHelper.unusedDevicePaths(basePath: base, fileManager: fileManager)
            for device in devices {
                if Task.isCancelled { break }
                let bytes = sizeCalculator.allocatedSize(at: device.path, policy: sizingPolicy)
                resolvedPaths.append(ResolvedPath(
                    path: device.path,
                    displayName: device.name,
                    targetID: target.id,
                    estimatedBytes: bytes,
                    isSelected: false
                ))
            }
            return TargetScanResult(target: target, resolvedPaths: resolvedPaths, scanErrors: scanErrors)
        }

        if target.action == .tmutilDeleteSnapshot {
            for snapshot in TimeMachineSnapshotHelper.listSnapshots() {
                resolvedPaths.append(ResolvedPath(
                    path: snapshot.dateToken,
                    displayName: snapshot.displayName,
                    targetID: target.id,
                    // tmutil reports no per-snapshot size; real reclaim shows in the free-space delta.
                    estimatedBytes: 0,
                    isSelected: false
                ))
            }
            return TargetScanResult(target: target, resolvedPaths: resolvedPaths, scanErrors: scanErrors)
        }

        let paths = pathsForScan(target: target, options: options)

        for path in paths {
            if Task.isCancelled { break }
            switch validator.validateDeletionPath(path, for: target) {
            case .failure(let error):
                scanErrors.append("\(path): \(error)")
                continue
            case .success:
                break
            }

            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { continue }

            if target.respectsLogAgeThreshold {
                let agedFiles = logFilesOlderThan(days: options.logAgeThresholdDays, in: path)
                for file in agedFiles {
                    if Task.isCancelled { break }
                    let bytes = sizeCalculator.allocatedSize(at: file, policy: sizingPolicy)
                    resolvedPaths.append(ResolvedPath(
                        path: file,
                        displayName: (file as NSString).lastPathComponent,
                        targetID: target.id,
                        estimatedBytes: bytes,
                        isSelected: target.needsUserSelection ? false : true
                    ))
                }
            } else if target.deletesContentsNotDirectory && isDir.boolValue {
                if let children = try? fileManager.contentsOfDirectory(atPath: path) {
                    for child in children {
                        if Task.isCancelled { break }
                        let childPath = (path as NSString).appendingPathComponent(child)
                        if case .failure = validator.validateDeletionPath(childPath, for: target) { continue }
                        let bytes = sizeCalculator.allocatedSize(at: childPath, policy: sizingPolicy)
                        resolvedPaths.append(ResolvedPath(
                            path: childPath,
                            displayName: (childPath as NSString).lastPathComponent,
                            targetID: target.id,
                            estimatedBytes: bytes,
                            isSelected: target.needsUserSelection ? false : true
                        ))
                    }
                }
            } else {
                let bytes = sizeCalculator.allocatedSize(at: path, policy: sizingPolicy)
                resolvedPaths.append(ResolvedPath(
                    path: path,
                    displayName: (path as NSString).lastPathComponent,
                    targetID: target.id,
                    estimatedBytes: bytes,
                    isSelected: target.needsUserSelection ? false : true
                ))
            }
        }

        return TargetScanResult(target: target, resolvedPaths: resolvedPaths, scanErrors: scanErrors)
    }

    private func pathsForScan(target: CleanupTarget, options: CleanerOptions) -> [String] {
        if target.usesDynamicPaths {
            return validator.resolveAllowlistedPaths(for: target)
        }
        return target.pathTemplates.map { validator.expandPath($0) }
    }

    private func logFilesOlderThan(days: Int, in directory: String) -> [String] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [String] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            results.append(url.path)
        }
        return results
    }

    // MARK: - Delete

    public func delete(
        levelResult: LevelScanResult,
        options: CleanerOptions
    ) async -> DeletionResult {
        let pathsToDelete = levelResult.selectedPaths
        return await delete(paths: pathsToDelete, targets: levelResult.targetResults.map(\.target), options: options)
    }

    public func delete(
        paths: [ResolvedPath],
        targets: [CleanupTarget],
        options: CleanerOptions
    ) async -> DeletionResult {
        await Task.detached(priority: .userInitiated) { [self] in
            self.deleteSync(paths: paths, targets: targets, options: options)
        }.value
    }

    private func deleteSync(
        paths: [ResolvedPath],
        targets: [CleanupTarget],
        options: CleanerOptions
    ) -> DeletionResult {
        let targetMap = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
        // Resolve each target's allowlist roots ONCE. Dynamic targets shell out
        // (e.g. `simctl list`) or scan directories, so re-resolving per path would
        // repeat that work for every item in a multi-item delete.
        let rootsByTargetID = Dictionary(uniqueKeysWithValues: targets.map {
            ($0.id, validator.resolveAllowlistedPaths(for: $0))
        })
        var entries: [DeletionEntry] = []
        var skipped: [(String, String)] = []
        let freeBefore = diskMonitor.availableCapacityBytes()
        var bytesFreed: Int64 = 0
        let useTrash = options.effectiveMoveToTrash

        for resolved in paths {
            guard let target = targetMap[resolved.targetID] else {
                skipped.append((resolved.path, "Unknown target"))
                continue
            }

            // External commands carry no real filesystem path: dispatch on the typed
            // action and skip path validation (there is nothing to validate).
            switch target.action {
            case .simctlDeleteUnavailable:
                let result = runSimctlDeleteUnavailable(dryRun: options.dryRun)
                bytesFreed += result.bytes
                entries.append(contentsOf: result.entries)
                if let error = result.error { skipped.append((resolved.path, error)) }
                continue
            case .dockerPrune:
                let result = runDockerPrune(dryRun: options.dryRun)
                bytesFreed += result.bytes
                entries.append(contentsOf: result.entries)
                if let error = result.error { skipped.append((resolved.path, error)) }
                continue
            case .tmutilDeleteSnapshot:
                let result = runTmutilDeleteSnapshot(token: resolved.path, dryRun: options.dryRun)
                bytesFreed += result.bytes
                entries.append(contentsOf: result.entries)
                if let error = result.error { skipped.append((resolved.path, error)) }
                continue
            case .files, .simctlDeleteDevice:
                break
            }

            let roots = rootsByTargetID[resolved.targetID] ?? []
            switch validator.validateDeletionPath(resolved.path, for: target, allowlistedRoots: roots) {
            case .failure(let error):
                skipped.append((resolved.path, String(describing: error)))
                continue
            case .success:
                break
            }

            let sizeBefore = sizeCalculator.allocatedSize(at: resolved.path)

            if options.dryRun {
                let entry = DeletionEntry(path: resolved.path, bytes: sizeBefore, movedToTrash: false, dryRun: true, targetID: target.id)
                entries.append(entry)
                try? deletionLog.append(entry)
                bytesFreed += sizeBefore
                continue
            }

            do {
                // Deleting a simulator goes through `simctl` (it also unregisters the
                // device), not a raw filesystem remove. The path was validated above.
                if target.action == .simctlDeleteDevice {
                    try runSimctlDelete(udid: (resolved.path as NSString).lastPathComponent)
                    let entry = DeletionEntry(path: resolved.path, bytes: sizeBefore, movedToTrash: false, dryRun: false, targetID: target.id)
                    entries.append(entry)
                    try? deletionLog.append(entry)
                    bytesFreed += sizeBefore
                    continue
                }

                // Targets whose destination is the Trash (Empty Trash) must always delete
                // permanently, even on a Safe-undo clean, or they would just shuffle items
                // within the Trash and reclaim nothing.
                let moveThisToTrash = useTrash && !target.bypassesTrash
                let standardized = (resolved.path as NSString).standardizingPath
                let isRoot = roots.contains { ($0 as NSString).standardizingPath == standardized }

                var trashedPath: String?
                if target.deletesContentsNotDirectory && isRoot {
                    try deleteDirectoryContents(at: resolved.path, target: target, moveToTrash: moveThisToTrash)
                } else {
                    trashedPath = try deleteItem(at: resolved.path, moveToTrash: moveThisToTrash)?.path
                }
                let entry = DeletionEntry(
                    path: resolved.path,
                    bytes: sizeBefore,
                    movedToTrash: moveThisToTrash,
                    dryRun: false,
                    trashedPath: trashedPath,
                    targetID: target.id
                )
                entries.append(entry)
                try? deletionLog.append(entry)
                bytesFreed += sizeBefore
            } catch {
                skipped.append((resolved.path, error.localizedDescription))
            }
        }

        let freeAfter = diskMonitor.availableCapacityBytes()
        return DeletionResult(
            entries: entries,
            bytesFreed: bytesFreed,
            skippedPaths: skipped,
            freeSpaceBefore: freeBefore,
            freeSpaceAfter: freeAfter
        )
    }

    private func deleteDirectoryContents(at path: String, target: CleanupTarget, moveToTrash: Bool) throws {
        guard let children = try? fileManager.contentsOfDirectory(atPath: path) else { return }
        for child in children {
            let childPath = (path as NSString).appendingPathComponent(child)
            guard case .success = validator.validateDeletionPath(childPath, for: target) else { continue }
            try deleteItem(at: childPath, moveToTrash: moveToTrash)
        }
    }

    @discardableResult
    private func deleteItem(at path: String, moveToTrash: Bool) throws -> URL? {
        let url = URL(fileURLWithPath: path)
        if isSymlink(at: url) {
            throw SafetyError.symlinkRefusal(path)
        }

        if moveToTrash {
            var resulting: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resulting)
            return resulting as URL?
        }
        try fileManager.removeItem(at: url)
        return nil
    }

    private func isSymlink(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    // MARK: - Undo (trash window)

    /// Move trashed items back to their original locations.
    ///
    /// Both sides of the move are validated: the source must resolve inside the user's
    /// Trash, and the destination must pass `SafetyValidator` against the entry's recorded
    /// cleanup target. A crafted or stale entry can neither pull files from outside the
    /// Trash nor plant them outside the allowlist (say, into LaunchAgents). Entries
    /// without target metadata are refused rather than guessed at.
    @discardableResult
    public func restore(_ entries: [DeletionEntry]) -> RestoreResult {
        var restored = 0
        var failures: [(path: String, reason: String)] = []
        for entry in entries {
            guard let trashed = entry.trashedPath else {
                failures.append((entry.path, "No trashed copy recorded"))
                continue
            }
            guard isInsideTrash(trashed) else {
                failures.append((entry.path, "Trashed copy is not inside the Trash"))
                continue
            }
            guard let targetID = entry.targetID,
                  let target = CleanupTargetRegistry.all.first(where: { $0.id == targetID }) else {
                failures.append((entry.path, "No cleanup target recorded for this entry"))
                continue
            }
            if case .failure(let error) = validator.validateRestoreDestination(entry.path, for: target) {
                failures.append((entry.path, String(describing: error)))
                continue
            }
            let dest = URL(fileURLWithPath: entry.path)
            do {
                try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: URL(fileURLWithPath: trashed), to: dest)
                restored += 1
            } catch {
                failures.append((entry.path, error.localizedDescription))
            }
        }
        return RestoreResult(restoredCount: restored, failures: failures)
    }

    /// Permanently remove trashed items (reclaims space once the undo window closes).
    ///
    /// Guarded to the user's Trash so a crafted entry can never make this delete a path
    /// outside the Trash. Returns the count permanently removed.
    @discardableResult
    public func purge(_ entries: [DeletionEntry]) -> Int {
        var purged = 0
        for entry in entries {
            guard let trashed = entry.trashedPath, isInsideTrash(trashed) else { continue }
            if (try? fileManager.removeItem(at: URL(fileURLWithPath: trashed))) != nil {
                purged += 1
            }
        }
        return purged
    }

    /// True only when `path` is the user's Trash or a descendant of it. Dusty operates on the
    /// boot volume, where `trashItem` lands files in `~/.Trash`, so that is the trusted boundary.
    private func isInsideTrash(_ path: String) -> Bool {
        let trash = (homeDirectory.path as NSString).appendingPathComponent(".Trash")
        let standardized = (path as NSString).standardizingPath
        return standardized == trash || standardized.hasPrefix(trash + "/")
    }

    // MARK: - External commands

    private struct CommandResult {
        let bytes: Int64
        let entries: [DeletionEntry]
        let error: String?
    }

    private func runSimctlDelete(udid: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "delete", udid]
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "simctl delete failed"
            throw NSError(domain: "Dusty.simctl", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: err.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
    }

    private func runSimctlDeleteUnavailable(dryRun: Bool) -> CommandResult {
        if dryRun {
            return CommandResult(bytes: 0, entries: [
                DeletionEntry(path: "simctl delete unavailable", bytes: 0, movedToTrash: false, dryRun: true)
            ], error: nil)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "delete", "unavailable"]
        let errPipe = Pipe()
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "simctl failed"
                return CommandResult(bytes: 0, entries: [], error: err.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let entry = DeletionEntry(path: "simctl delete unavailable", bytes: 0, movedToTrash: false, dryRun: false)
            try? deletionLog.append(entry)
            return CommandResult(bytes: 0, entries: [entry], error: nil)
        } catch {
            return CommandResult(bytes: 0, entries: [], error: error.localizedDescription)
        }
    }

    private func runTmutilDeleteSnapshot(token: String, dryRun: Bool) -> CommandResult {
        if dryRun {
            return CommandResult(bytes: 0, entries: [
                DeletionEntry(path: "tmutil deletelocalsnapshots \(token)", bytes: 0, movedToTrash: false, dryRun: true)
            ], error: nil)
        }
        guard TimeMachineSnapshotHelper.deleteSnapshot(dateToken: token) else {
            return CommandResult(bytes: 0, entries: [], error: "Snapshot \(token) could not be removed")
        }
        // tmutil reports no freed bytes; the real reclaim shows in the result's free-space delta.
        let entry = DeletionEntry(path: "tmutil deletelocalsnapshots \(token)", bytes: 0, movedToTrash: false, dryRun: false)
        try? deletionLog.append(entry)
        return CommandResult(bytes: 0, entries: [entry], error: nil)
    }

    private func runDockerPrune(dryRun: Bool) -> CommandResult {
        let dockerPath = ["/opt/homebrew/bin/docker", "/usr/local/bin/docker"].first { fileManager.fileExists(atPath: $0) }
        guard let docker = dockerPath else {
            return CommandResult(bytes: 0, entries: [], error: "Docker not installed")
        }

        if dryRun {
            let bytes = estimateDockerReclaimable()
            return CommandResult(bytes: bytes, entries: [
                DeletionEntry(path: "docker system prune", bytes: bytes, movedToTrash: false, dryRun: true)
            ], error: nil)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: docker)
        // Prune unused images, build cache, stopped containers and networks. We
        // intentionally omit `--volumes`: anonymous volumes routinely hold real
        // data (databases, uploads, dev state) that cannot be re-downloaded.
        process.arguments = ["system", "prune", "-af"]
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if process.terminationStatus != 0 {
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "docker prune failed"
                return CommandResult(bytes: 0, entries: [], error: err.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let bytes = parseDockerReclaimed(from: output)
            let entry = DeletionEntry(path: "docker system prune", bytes: bytes, movedToTrash: false, dryRun: false)
            try? deletionLog.append(entry)
            return CommandResult(bytes: bytes, entries: [entry], error: nil)
        } catch {
            return CommandResult(bytes: 0, entries: [], error: error.localizedDescription)
        }
    }

    private func estimateDockerReclaimable() -> Int64 {
        let dockerPath = ["/opt/homebrew/bin/docker", "/usr/local/bin/docker"].first { fileManager.fileExists(atPath: $0) }
        guard let docker = dockerPath else { return 0 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: docker)
        process.arguments = ["system", "df", "--format", "{{.Reclaimable}}"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return parseDockerReclaimableLines(output)
        } catch {
            return 0
        }
    }

    private func parseDockerReclaimableLines(_ output: String) -> Int64 {
        output.split(separator: "\n").reduce(0) { total, line in
            total + (parseDockerSize(String(line).trimmingCharacters(in: .whitespaces)) ?? 0)
        }
    }

    private func parseDockerReclaimed(from output: String) -> Int64 {
        for line in output.split(separator: "\n") {
            if line.contains("Total reclaimed space:") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    return parseDockerSize(String(parts[1]).trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
        }
        return 0
    }

    /// Parse a docker CLI size like "591.7MB" or "1.082TB". `{{.Reclaimable}}` appends a
    /// percentage ("591.7MB (4%)"), so anything from the first parenthesis on is dropped.
    /// Docker prints decimal units (go-units): kB is 1000 bytes, GB is 10^9, up to PB.
    private func parseDockerSize(_ s: String) -> Int64? {
        var trimmed = s.trimmingCharacters(in: .whitespaces)
        if let paren = trimmed.firstIndex(of: "(") {
            trimmed = String(trimmed[..<paren]).trimmingCharacters(in: .whitespaces)
        }
        if trimmed == "0B" || trimmed == "0" { return 0 }
        let units: [(String, Double)] = [
            ("PB", 1e15), ("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3), ("kB", 1e3), ("B", 1)
        ]
        for (suffix, multiplier) in units {
            if trimmed.hasSuffix(suffix) {
                let num = trimmed.dropLast(suffix.count)
                if let d = Double(num.trimmingCharacters(in: .whitespaces)) {
                    return Int64(d * multiplier)
                }
            }
        }
        return nil
    }
}

// MARK: - Scan progress

/// Thread-safe completion counter so a bounded, concurrent scan can report monotonic
/// progress as each target finishes (the order targets finish in is not deterministic).
private actor ScanProgressCounter {
    private var count = 0
    func increment() -> Int {
        count += 1
        return count
    }
}

// MARK: - Test helpers

extension CleanerEngine {
    public func validatePath(_ path: String, for target: CleanupTarget) -> Result<Void, SafetyError> {
        validator.validateDeletionPath(path, for: target)
    }

    public func expandPath(_ template: String) -> String {
        validator.expandPath(template)
    }

    /// Exposes the private Docker size parser for unit testing.
    public func parseDockerSizeForTesting(_ s: String) -> Int64? {
        parseDockerSize(s)
    }
}

extension SafetyError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .pathNotInAllowlist(let p): return "Not in allowlist: \(p)"
        case .prohibitedPath(let p): return "Prohibited path: \(p)"
        case .symlinkRefusal(let p): return "Symlink refused: \(p)"
        case .outsideBootVolume(let p): return "Outside boot volume: \(p)"
        case .pathTraversal(let p): return "Path traversal: \(p)"
        case .invalidPath(let p): return "Invalid path: \(p)"
        }
    }
}
