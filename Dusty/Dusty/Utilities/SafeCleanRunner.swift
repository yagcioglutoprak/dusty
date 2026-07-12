import Foundation
import CleanerEngine

/// An unattended clean with nobody watching: scheduled auto-clean, the reactive
/// low-disk clean, and the Shortcuts action all run through here so they behave
/// identically to the panel's Clean button. Auto-selected items only, app-open
/// targets skipped, items pass through the Trash and are purged right away
/// (there is no one in front of an undo window, and the reactive clean exists
/// to free space, which items sitting in the Trash do not), and the result
/// lands in the stats. Defaults to Safe; the settings can widen the scope to
/// include Developer caches.
@MainActor
enum SafeCleanRunner {
    struct Outcome {
        let bytesFreed: Int64
        let itemCount: Int
        let skippedApps: [String]
    }

    static func run(engine: CleanerEngine, levels: [CleanupLevel] = [.safe]) async -> Outcome? {
        // Refuse to start if any clean (panel, Shortcuts, or auto-clean) is already in
        // flight: two deletes over the same targets would race on the filesystem and
        // skew the stats. nil here means "busy", distinct from a real failure.
        guard CleanCoordinator.shared.beginClean() else { return nil }
        defer { CleanCoordinator.shared.endClean() }

        let scan = await engine.scan(levels: Set(levels), sizingPolicy: .cached)
        var totalBytesFreed: Int64 = 0
        var totalItemCount = 0
        var skippedApps: Set<String> = []

        for level in levels {
            guard let levelResult = scan.levelResults[level] else { continue }

            let blocked = Set(levelResult.targetResults.compactMap { tr -> String? in
                let t = tr.target
                guard t.requiresAppClosed != nil || t.requiresAppBundleID != nil,
                      AppProcessChecker.isRunning(name: t.requiresAppClosed, bundleID: t.requiresAppBundleID)
                else { return nil }
                return tr.id
            })
            skippedApps.formUnion(
                levelResult.targetResults
                    .filter { blocked.contains($0.id) && !$0.resolvedPaths.isEmpty }
                    .compactMap(\.target.requiresAppClosed)
            )
            let paths = levelResult.selectedPaths.filter { !blocked.contains($0.targetID) }
            guard !paths.isEmpty else { continue }

            // Deleting per level keeps the options honest (`cleanupLevel` feeds the
            // engine's Trash semantics) and the stats broken out the way the panel
            // records them.
            var options = CleanerOptions()
            options.cleanupLevel = level
            options.trashForUndo = true

            let result = await engine.delete(paths: paths, targets: levelResult.targetResults.map(\.target), options: options)
            let trashed = result.entries.filter { $0.trashedPath != nil }
            if !trashed.isEmpty {
                _ = await Task.detached { engine.purge(trashed) }.value
            }
            if result.bytesFreed > 0 {
                CleanStatsStore.shared.record(level: level, bytes: result.bytesFreed, items: result.entries.count)
            }
            totalBytesFreed += result.bytesFreed
            totalItemCount += result.entries.count
        }

        return Outcome(bytesFreed: totalBytesFreed, itemCount: totalItemCount, skippedApps: skippedApps.sorted())
    }
}
