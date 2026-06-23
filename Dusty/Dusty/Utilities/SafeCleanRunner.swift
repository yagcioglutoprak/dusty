import Foundation
import CleanerEngine

/// A Safe-level clean with nobody watching: scheduled auto-clean and the
/// Shortcuts action both run through here so they behave identically to the
/// panel's Clean Safe button. Auto-selected items only, app-open targets
/// skipped, items pass through the Trash and are purged right away (there is
/// no one in front of an undo window), and the result lands in the stats.
@MainActor
enum SafeCleanRunner {
    struct Outcome {
        let bytesFreed: Int64
        let itemCount: Int
        let skippedApps: [String]
    }

    static func run(engine: CleanerEngine) async -> Outcome? {
        // Refuse to start if any clean (panel, Shortcuts, or auto-clean) is already in
        // flight: two deletes over the same targets would race on the filesystem and
        // skew the stats. nil here means "busy", distinct from a real failure.
        guard CleanCoordinator.shared.beginClean() else { return nil }
        defer { CleanCoordinator.shared.endClean() }

        let scan = await engine.scan(levels: [.safe], sizingPolicy: .cached)
        guard let levelResult = scan.levelResults[.safe] else { return nil }

        let blocked = Set(levelResult.targetResults.compactMap { tr -> String? in
            let t = tr.target
            guard t.requiresAppClosed != nil || t.requiresAppBundleID != nil,
                  AppProcessChecker.isRunning(name: t.requiresAppClosed, bundleID: t.requiresAppBundleID)
            else { return nil }
            return tr.id
        })
        let skippedApps = levelResult.targetResults
            .filter { blocked.contains($0.id) && !$0.resolvedPaths.isEmpty }
            .compactMap(\.target.requiresAppClosed)
            .sorted()
        let paths = levelResult.selectedPaths.filter { !blocked.contains($0.targetID) }
        guard !paths.isEmpty else {
            return Outcome(bytesFreed: 0, itemCount: 0, skippedApps: skippedApps)
        }

        var options = CleanerOptions()
        options.cleanupLevel = .safe
        options.trashForUndo = true

        let result = await engine.delete(paths: paths, targets: levelResult.targetResults.map(\.target), options: options)
        let trashed = result.entries.filter { $0.trashedPath != nil }
        if !trashed.isEmpty {
            _ = await Task.detached { engine.purge(trashed) }.value
        }
        if result.bytesFreed > 0 {
            CleanStatsStore.shared.record(level: .safe, bytes: result.bytesFreed, items: result.entries.count)
        }
        return Outcome(bytesFreed: result.bytesFreed, itemCount: result.entries.count, skippedApps: skippedApps)
    }
}
