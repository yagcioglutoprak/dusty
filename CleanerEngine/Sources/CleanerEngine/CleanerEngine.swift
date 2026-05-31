import Foundation

/// Pure cleanup engine: no SwiftUI dependencies. Fully unit-testable.
public final class CleanerEngine: @unchecked Sendable {
    private let fileManager: FileManager
    private let validator: SafetyValidator
    private let sizeCalculator: SizeCalculator
    private let diskMonitor: DiskSpaceMonitor
    private let deletionLog: DeletionLogStore

    public init(
        fileManager: FileManager = .default,
        validator: SafetyValidator? = nil,
        sizeCalculator: SizeCalculator? = nil,
        diskMonitor: DiskSpaceMonitor? = nil,
        deletionLog: DeletionLogStore? = nil
    ) {
        self.fileManager = fileManager
        self.validator = validator ?? SafetyValidator(fileManager: fileManager)
        self.sizeCalculator = sizeCalculator ?? SizeCalculator(fileManager: fileManager)
        self.diskMonitor = diskMonitor ?? DiskSpaceMonitor(fileManager: fileManager)
        self.deletionLog = deletionLog ?? FileDeletionLogStore(fileManager: fileManager)
    }

    public var logFileURL: URL { deletionLog.logFileURL }

    // MARK: - Scan

    public func scan(
        levels: Set<CleanupLevel> = Set(CleanupLevel.allCases),
        options: CleanerOptions = CleanerOptions(),
        progress: ScanProgressHandler? = nil
    ) async -> FullScanResult {
        let targets = CleanupLevel.allCases
            .filter { levels.contains($0) }
            .flatMap { CleanupTargetRegistry.targets(for: $0) }

        var resultsByTargetID: [String: TargetScanResult] = [:]
        let total = targets.count

        await withTaskGroup(of: (String, TargetScanResult, String).self) { group in
            for target in targets {
                group.addTask { [self] in
                    let result = await self.scanTarget(target, options: options)
                    return (target.id, result, target.displayName)
                }
            }
            var completed = 0
            for await (id, result, name) in group {
                completed += 1
                resultsByTargetID[id] = result
                progress?(ScanProgress(completed: completed, total: total, currentTargetName: name))
            }
        }

        var levelResults: [CleanupLevel: LevelScanResult] = [:]
        for level in CleanupLevel.allCases where levels.contains(level) {
            let levelTargets = CleanupTargetRegistry.targets(for: level)
            let targetResults = levelTargets.compactMap { resultsByTargetID[$0.id] }
            levelResults[level] = LevelScanResult(level: level, targetResults: targetResults)
        }

        return FullScanResult(levelResults: levelResults)
    }

    public func scanTarget(_ target: CleanupTarget, options: CleanerOptions) async -> TargetScanResult {
        scanTargetSync(target, options: options)
    }

    private func scanTargetSync(_ target: CleanupTarget, options: CleanerOptions) -> TargetScanResult {
        if Task.isCancelled { return TargetScanResult(target: target, resolvedPaths: []) }
        var scanErrors: [String] = []
        var resolvedPaths: [ResolvedPath] = []

        if target.id == "simulator-unavailable" {
            let udids = SimulatorHelper.unavailableDeviceUDIDs()
            let base = validator.expandPath("~/Library/Developer/CoreSimulator/Devices")
            let bytes = udids.reduce(Int64(0)) { sum, udid in
                sum + sizeCalculator.allocatedSize(at: (base as NSString).appendingPathComponent(udid))
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

        if target.id == "docker-prune" {
            if validator.resolveAllowlistedPaths(for: target).isEmpty {
                return TargetScanResult(target: target, resolvedPaths: [], scanErrors: ["Docker not installed"])
            }
            let bytes = estimateDockerReclaimable()
            resolvedPaths.append(ResolvedPath(
                path: "docker:system prune",
                displayName: "All unused images, build cache & anonymous volumes",
                targetID: target.id,
                estimatedBytes: bytes,
                isSelected: false
            ))
            return TargetScanResult(target: target, resolvedPaths: resolvedPaths)
        }

        if target.id == "old-simulators" {
            let base = validator.expandPath("~/Library/Developer/CoreSimulator/Devices")
            let devices = SimulatorHelper.unusedDevicePaths(basePath: base, fileManager: fileManager)
            for device in devices {
                let bytes = sizeCalculator.allocatedSize(at: device.path)
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
                    let bytes = sizeCalculator.allocatedSize(at: file)
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
                        let childPath = (path as NSString).appendingPathComponent(child)
                        if case .failure = validator.validateDeletionPath(childPath, for: target) { continue }
                        let bytes = sizeCalculator.allocatedSize(at: childPath)
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
                let bytes = sizeCalculator.allocatedSize(at: path)
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

            if resolved.path == "simctl:delete unavailable" {
                let result = runSimctlDeleteUnavailable(dryRun: options.dryRun)
                bytesFreed += result.bytes
                entries.append(contentsOf: result.entries)
                if let error = result.error { skipped.append((resolved.path, error)) }
                continue
            }

            if resolved.path == "docker:system prune" {
                let result = runDockerPrune(dryRun: options.dryRun)
                bytesFreed += result.bytes
                entries.append(contentsOf: result.entries)
                if let error = result.error { skipped.append((resolved.path, error)) }
                continue
            }

            switch validator.validateDeletionPath(resolved.path, for: target) {
            case .failure(let error):
                skipped.append((resolved.path, String(describing: error)))
                continue
            case .success:
                break
            }

            let sizeBefore = sizeCalculator.allocatedSize(at: resolved.path)

            if options.dryRun {
                let entry = DeletionEntry(path: resolved.path, bytes: sizeBefore, movedToTrash: false, dryRun: true)
                entries.append(entry)
                try? deletionLog.append(entry)
                bytesFreed += sizeBefore
                continue
            }

            do {
                let roots = target.pathTemplates.map { validator.expandPath($0) }
                let standardized = (resolved.path as NSString).standardizingPath
                let isRoot = roots.contains { ($0 as NSString).standardizingPath == standardized }

                var trashedPath: String?
                if target.id == "old-simulators" {
                    try runSimctlDelete(udid: (resolved.path as NSString).lastPathComponent)
                } else if target.deletesContentsNotDirectory && isRoot {
                    try deleteDirectoryContents(at: resolved.path, target: target, moveToTrash: useTrash)
                } else {
                    trashedPath = try deleteItem(at: resolved.path, moveToTrash: useTrash)?.path
                }
                let entry = DeletionEntry(
                    path: resolved.path,
                    bytes: sizeBefore,
                    movedToTrash: useTrash,
                    dryRun: false,
                    trashedPath: trashedPath
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

    // MARK: - Undo (Safe-level trash window)

    /// Move trashed items back to their original locations. Returns the count restored.
    @discardableResult
    public func restore(_ entries: [DeletionEntry]) -> Int {
        var restored = 0
        for entry in entries {
            guard let trashed = entry.trashedPath else { continue }
            let dest = URL(fileURLWithPath: entry.path)
            try? fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fileManager.moveItem(at: URL(fileURLWithPath: trashed), to: dest)) != nil {
                restored += 1
            }
        }
        return restored
    }

    /// Permanently remove trashed items (reclaims space once the undo window closes).
    public func purge(_ entries: [DeletionEntry]) {
        for entry in entries {
            guard let trashed = entry.trashedPath else { continue }
            try? fileManager.removeItem(at: URL(fileURLWithPath: trashed))
        }
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
        process.arguments = ["system", "prune", "-af", "--volumes"]
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

    private func parseDockerSize(_ s: String) -> Int64? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed == "0B" || trimmed == "0" { return 0 }
        let units: [(String, Int64)] = [("GB", 1_073_741_824), ("MB", 1_048_576), ("KB", 1024), ("kB", 1024), ("B", 1)]
        for (suffix, multiplier) in units {
            if trimmed.hasSuffix(suffix) {
                let num = trimmed.dropLast(suffix.count)
                if let d = Double(num.trimmingCharacters(in: .whitespaces)) {
                    return Int64(d * Double(multiplier))
                }
            }
        }
        return nil
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
