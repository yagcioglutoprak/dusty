import AppIntents
import CleanerEngine

/// Shortcuts actions. Both run the same engine and allowlist as the panel:
/// the clean intent is exactly the Clean Safe button, the size intent is a
/// read-only scan. Nothing here can reach manual-pick or opt-in targets.

struct CleanSafeIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean Safe Items"
    static let description = IntentDescription(
        "Deletes the auto-safe caches and logs Dusty found, exactly like the Clean Safe button. Targets whose app is open are skipped, and every deleted path is recorded in the deletion log."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard let outcome = await SafeCleanRunner.run(engine: CleanerEngine()) else {
            return .result(value: "0 B", dialog: "The scan failed, nothing was cleaned.")
        }
        let freed = DiskSpaceMonitor.formatBytes(outcome.bytesFreed)
        if outcome.itemCount == 0 {
            let skipped = outcome.skippedApps.isEmpty
                ? ""
                : " \(outcome.skippedApps.joined(separator: ", ")) was open, so its cache was skipped."
            return .result(value: freed, dialog: IntentDialog(stringLiteral: "Nothing safe to clean right now.\(skipped)"))
        }
        return .result(value: freed, dialog: IntentDialog(stringLiteral: "Cleaned \(outcome.itemCount) items, \(freed) freed."))
    }
}

struct GetReclaimableSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Reclaimable Space"
    static let description = IntentDescription(
        "Scans all three cleanup levels and returns how much space Dusty could reclaim. Read-only: deletes nothing."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let result = await CleanerEngine().scan(sizingPolicy: .cached)
        let total = DiskSpaceMonitor.formatBytes(result.totalBytes)
        let safe = DiskSpaceMonitor.formatBytes(result.levelResults[.safe]?.totalBytes ?? 0)
        return .result(value: total, dialog: IntentDialog(stringLiteral: "\(total) reclaimable (\(safe) of it safe to clean automatically)."))
    }
}

struct DustyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CleanSafeIntent(),
            phrases: [
                "Clean my Mac with \(.applicationName)",
                "Run a safe clean in \(.applicationName)"
            ],
            shortTitle: "Clean Safe",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: GetReclaimableSpaceIntent(),
            phrases: [
                "How much can \(.applicationName) clean",
                "Check reclaimable space in \(.applicationName)"
            ],
            shortTitle: "Reclaimable Space",
            systemImageName: "internaldrive"
        )
    }
}
