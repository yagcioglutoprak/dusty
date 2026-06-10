import Foundation
import AppKit
import CleanerEngine

// The dusty CLI: the same engine, allowlist, and safety rules as the menu bar app,
// scriptable from a terminal. Nothing is deleted without --yes, and items the app
// requires a manual pick for (installers, archives, simulators, Docker, models)
// are never touched from here.

let cliVersion = "1.5.0"

// MARK: - Output helpers

func formatBytes(_ bytes: Int64) -> String {
    DiskSpaceMonitor.formatBytes(bytes)
}

func errPrint(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func emitJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

// MARK: - Argument parsing

struct ParsedArgs {
    var command: String
    var level: String?
    var json = false
    var yes = false
    var dryRun = false
    var trash = false
}

func parseArgs(_ args: [String]) -> ParsedArgs? {
    guard let command = args.first, !command.hasPrefix("-") || command == "--version" else { return nil }
    var parsed = ParsedArgs(command: command == "--version" ? "version" : command)
    var rest = args.dropFirst()
    while let arg = rest.first {
        rest = rest.dropFirst()
        switch arg {
        case "--level", "-l":
            guard let value = rest.first else { return nil }
            rest = rest.dropFirst()
            parsed.level = value
        case "--json": parsed.json = true
        case "--yes", "-y": parsed.yes = true
        case "--dry-run", "-n": parsed.dryRun = true
        case "--trash", "-t": parsed.trash = true
        default: return nil
        }
    }
    return parsed
}

func levels(from name: String?, defaultAll: Bool) -> Set<CleanupLevel>? {
    switch (name ?? (defaultAll ? "all" : "safe")).lowercased() {
    case "all": return Set(CleanupLevel.allCases)
    case "safe", "1": return [.safe]
    case "developer", "dev", "2": return [.developer]
    case "deep", "3": return [.deep]
    default: return nil
    }
}

func levelName(_ level: CleanupLevel) -> String {
    switch level {
    case .safe: return "safe"
    case .developer: return "developer"
    case .deep: return "deep"
    }
}

let usage = """
dusty \(cliVersion) - macOS disk cleaner (allowlist-only, shows every path)

USAGE
  dusty scan    [--level safe|developer|deep|all] [--json]
  dusty clean   [--level safe|developer|deep] [--dry-run] [--trash] [--yes] [--json]
  dusty targets [--json]
  dusty version

COMMANDS
  scan      Measure reclaimable space (default: all levels). Deletes nothing.
  clean     Delete the auto-safe items at one level (default: safe).
            Prints the plan and exits unless --yes is given.
  targets   List every cleanup target in the allowlist.

OPTIONS
  --level, -l    Cleanup level: safe (1), developer (2), deep (3), or all (scan only)
  --dry-run, -n  Log what a clean would delete without deleting anything
  --trash, -t    Move items to the Trash instead of deleting them
  --yes, -y      Actually delete. Without it, clean only prints the plan.
  --json         Machine-readable output

Items the app gates behind a manual pick (old installers, Xcode archives,
simulators, Docker prune, Ollama models) are never cleaned from the CLI.
Targets whose app is currently open are skipped automatically.
"""

// MARK: - Running-app gate (same rule as the menu bar app)

func isAppRunning(name: String?, bundleID: String?) -> Bool {
    let apps = NSWorkspace.shared.runningApplications
    if let id = bundleID, apps.contains(where: { $0.bundleIdentifier == id }) { return true }
    if let name {
        return apps.contains { $0.localizedName?.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }
    return false
}

func blockedTargetIDs(in result: LevelScanResult) -> Set<String> {
    Set(result.targetResults.compactMap { tr in
        let t = tr.target
        guard t.requiresAppClosed != nil || t.requiresAppBundleID != nil,
              isAppRunning(name: t.requiresAppClosed, bundleID: t.requiresAppBundleID)
        else { return nil }
        return tr.id
    })
}

// MARK: - JSON shapes

struct TargetJSON: Encodable {
    let id: String
    let name: String
    let category: String
    let bytes: Int64
    let items: Int
    let autoSelected: Bool
    let skippedAppOpen: Bool
}

struct LevelJSON: Encodable {
    let level: Int
    let name: String
    let totalBytes: Int64
    let targets: [TargetJSON]
}

struct ScanJSON: Encodable {
    let scannedAt: Date
    let totalBytes: Int64
    let levels: [LevelJSON]
}

struct SkippedJSON: Encodable {
    let path: String
    let reason: String
}

struct CleanJSON: Encodable {
    let level: String
    let dryRun: Bool
    let movedToTrash: Bool
    let deletedItems: Int
    let bytesFreed: Int64
    let freeSpaceBefore: Int64
    let freeSpaceAfter: Int64
    let skipped: [SkippedJSON]
    let skippedOpenApps: [String]
}

// MARK: - Scan

func runScan(engine: CleanerEngine, levels: Set<CleanupLevel>, json: Bool) async -> Int32 {
    let showProgress = !json && isatty(fileno(stderr)) != 0
    let result = await engine.scan(levels: levels) { progress in
        if showProgress {
            FileHandle.standardError.write(Data("\r\u{1B}[KScanning \(progress.completed)/\(progress.total) \(progress.currentTargetName)".utf8))
        }
    }
    if showProgress {
        FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
    }

    let sortedLevels = CleanupLevel.allCases.filter { levels.contains($0) }

    if json {
        let levelsJSON = sortedLevels.compactMap { level -> LevelJSON? in
            guard let lr = result.levelResults[level] else { return nil }
            let blocked = blockedTargetIDs(in: lr)
            return LevelJSON(
                level: level.rawValue,
                name: levelName(level),
                totalBytes: lr.totalBytes,
                targets: lr.targetResults.filter { !$0.resolvedPaths.isEmpty }.map { tr in
                    TargetJSON(
                        id: tr.id,
                        name: tr.target.displayName,
                        category: tr.target.category,
                        bytes: tr.totalBytes,
                        items: tr.resolvedPaths.count,
                        autoSelected: !tr.target.needsUserSelection,
                        skippedAppOpen: blocked.contains(tr.id)
                    )
                }
            )
        }
        emitJSON(ScanJSON(scannedAt: result.scannedAt, totalBytes: result.totalBytes, levels: levelsJSON))
        return 0
    }

    for level in sortedLevels {
        guard let lr = result.levelResults[level] else { continue }
        let blocked = blockedTargetIDs(in: lr)
        print("\(level.title) - \(formatBytes(lr.totalBytes))")
        let rows = lr.targetResults.filter { !$0.resolvedPaths.isEmpty }.sorted { $0.totalBytes > $1.totalBytes }
        for tr in rows {
            var note = ""
            if blocked.contains(tr.id) { note = "  (skipped: \(tr.target.requiresAppClosed ?? "app") is open)" }
            else if tr.target.needsUserSelection { note = "  (manual pick in the app)" }
            let size = formatBytes(tr.totalBytes).padding(toLength: 10, withPad: " ", startingAt: 0)
            print("  \(size) \(tr.target.displayName)\(note)")
        }
        if rows.isEmpty { print("  nothing found") }
        print("")
    }
    print("Total reclaimable: \(formatBytes(result.totalBytes))")
    return 0
}

// MARK: - Clean

func runClean(engine: CleanerEngine, level: CleanupLevel, args: ParsedArgs) async -> Int32 {
    let showProgress = !args.json && isatty(fileno(stderr)) != 0
    let scan = await engine.scan(levels: [level]) { progress in
        if showProgress {
            FileHandle.standardError.write(Data("\r\u{1B}[KScanning \(progress.completed)/\(progress.total) \(progress.currentTargetName)".utf8))
        }
    }
    if showProgress { FileHandle.standardError.write(Data("\r\u{1B}[K".utf8)) }

    guard let levelResult = scan.levelResults[level] else {
        errPrint("Scan failed for level \(levelName(level)).")
        return 1
    }

    let blocked = blockedTargetIDs(in: levelResult)
    let skippedApps = levelResult.targetResults
        .filter { blocked.contains($0.id) && !$0.resolvedPaths.isEmpty }
        .compactMap(\.target.requiresAppClosed)
        .sorted()
    // Auto-selected items only (manual-pick targets scan unselected), minus open apps.
    let paths = levelResult.selectedPaths.filter { !blocked.contains($0.targetID) }
    let planBytes = paths.reduce(0) { $0 + $1.estimatedBytes }

    if paths.isEmpty {
        if args.json {
            emitJSON(CleanJSON(level: levelName(level), dryRun: args.dryRun, movedToTrash: args.trash,
                               deletedItems: 0, bytesFreed: 0, freeSpaceBefore: 0, freeSpaceAfter: 0,
                               skipped: [], skippedOpenApps: skippedApps))
        } else {
            print("Nothing to clean at level \(levelName(level)).")
            for app in skippedApps { print("Skipped \(app): quit it to clean its cache.") }
        }
        return 0
    }

    if !args.yes && !args.dryRun {
        // Plan only. The full path list is the product's whole point: show it.
        print("Would delete \(paths.count) item\(paths.count == 1 ? "" : "s") (\(formatBytes(planBytes))) at level \(levelName(level)):\n")
        for path in paths.sorted(by: { $0.estimatedBytes > $1.estimatedBytes }) {
            print("  \(formatBytes(path.estimatedBytes).padding(toLength: 10, withPad: " ", startingAt: 0)) \(path.path)")
        }
        for app in skippedApps { print("\nSkipped \(app): quit it to clean its cache.") }
        print("\nNothing deleted. Re-run with --yes to delete\(args.trash ? " (items go to the Trash)" : ""), or --dry-run to log only.")
        return 0
    }

    var options = CleanerOptions()
    options.dryRun = args.dryRun
    options.cleanupLevel = level
    options.trashForUndo = args.trash && !args.dryRun

    let result = await engine.delete(paths: paths, targets: levelResult.targetResults.map(\.target), options: options)

    if args.json {
        emitJSON(CleanJSON(
            level: levelName(level),
            dryRun: args.dryRun,
            movedToTrash: args.trash && !args.dryRun,
            deletedItems: result.entries.count,
            bytesFreed: result.bytesFreed,
            freeSpaceBefore: result.freeSpaceBefore,
            freeSpaceAfter: result.freeSpaceAfter,
            skipped: result.skippedPaths.map { SkippedJSON(path: $0.path, reason: $0.reason) },
            skippedOpenApps: skippedApps
        ))
    } else {
        if args.dryRun {
            print("Dry run: \(result.entries.count) items, \(formatBytes(result.bytesFreed)) would be freed. Nothing deleted.")
        } else if args.trash {
            print("Moved \(result.entries.count) items (\(formatBytes(result.bytesFreed))) to the Trash.")
        } else {
            print("Cleaned \(result.entries.count) items, \(formatBytes(result.bytesFreed)) freed.")
        }
        for app in skippedApps { print("Skipped \(app): quit it to clean its cache.") }
        if !result.skippedPaths.isEmpty {
            print("\(result.skippedPaths.count) item\(result.skippedPaths.count == 1 ? "" : "s") skipped:")
            for skip in result.skippedPaths.prefix(20) { print("  \(skip.path): \(skip.reason)") }
        }
        print("Deletion log: \(engine.logFileURL.path)")
    }
    return result.entries.isEmpty && !result.skippedPaths.isEmpty ? 1 : 0
}

// MARK: - Targets

func runTargets(json: Bool) -> Int32 {
    if json {
        struct Entry: Encodable {
            let id: String
            let name: String
            let level: Int
            let category: String
            let paths: [String]
            let manualPick: Bool
        }
        emitJSON(CleanupTargetRegistry.all.map {
            Entry(id: $0.id, name: $0.displayName, level: $0.level.rawValue,
                  category: $0.category, paths: $0.pathTemplates, manualPick: $0.needsUserSelection)
        })
        return 0
    }
    for level in CleanupLevel.allCases {
        print("\(level.title)")
        for target in CleanupTargetRegistry.targets(for: level) {
            let mark = target.needsUserSelection ? " (manual pick)" : ""
            print("  \(target.displayName)\(mark)")
            for template in target.pathTemplates { print("      \(template)") }
        }
        print("")
    }
    return 0
}

// MARK: - Entry point

let rawArgs = Array(CommandLine.arguments.dropFirst())

guard let args = parseArgs(rawArgs.isEmpty ? ["help"] : rawArgs) else {
    errPrint(usage)
    exit(64)
}

switch args.command {
case "help", "--help", "-h":
    print(usage)
case "version":
    print("dusty \(cliVersion)")
case "targets":
    exit(runTargets(json: args.json))
case "scan":
    guard let levelSet = levels(from: args.level, defaultAll: true) else {
        errPrint("Unknown level '\(args.level ?? "")'. Use safe, developer, deep, or all.")
        exit(64)
    }
    let engine = CleanerEngine()
    exit(await runScan(engine: engine, levels: levelSet, json: args.json))
case "clean":
    guard let levelSet = levels(from: args.level, defaultAll: false), levelSet.count == 1,
          let level = levelSet.first else {
        errPrint("clean needs a single level: safe, developer, or deep.")
        exit(64)
    }
    let engine = CleanerEngine()
    exit(await runClean(engine: engine, level: level, args: args))
default:
    errPrint(usage)
    exit(64)
}
