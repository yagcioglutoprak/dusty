import AppIntents
import AppKit
import CleanerEngine

/// Shortcuts actions. They run the same engine and allowlist as the panel:
/// the clean intent is exactly the Clean Safe button, the size intent is a
/// read-only scan, and the memory intent only reads. Nothing here can reach
/// manual-pick or opt-in targets, and nothing here quits an app.

struct CleanSafeIntent: AppIntent {
    static let title = LocalizedStringResource(
        "intent.cleanSafe.title",
        defaultValue: "Clean Safe Items"
    )
    static let description = IntentDescription(
        LocalizedStringResource(
            "intent.cleanSafe.description",
            defaultValue: "Deletes the auto-safe caches and logs Dusty found, exactly like the Clean Safe button. Targets whose app is open are skipped, and every deleted path is recorded in the deletion log."
        )
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        if CleanCoordinator.shared.isCleaning {
            return .result(value: "0 B", dialog: IntentDialog(stringLiteral:
                L10n.t("intent.cleanSafe.busy", "Dusty is already cleaning. Try again in a moment.")))
        }
        guard let outcome = await SafeCleanRunner.run(engine: CleanerEngine()) else {
            return .result(value: "0 B", dialog: IntentDialog(stringLiteral:
                L10n.t("intent.cleanSafe.scanFailed", "The scan failed, nothing was cleaned.")))
        }
        let freed = DiskSpaceMonitor.formatBytes(outcome.bytesFreed)
        if outcome.itemCount == 0 {
            let message = outcome.skippedApps.isEmpty
                ? L10n.t("intent.cleanSafe.nothing", "Nothing safe to clean right now.")
                : L10n.f("intent.cleanSafe.nothingSkipped",
                         "Nothing safe to clean right now. %@ was open, so its cache was skipped.",
                         outcome.skippedApps.formatted(.list(type: .and)))
            return .result(value: freed, dialog: IntentDialog(stringLiteral: message))
        }
        return .result(value: freed, dialog: IntentDialog(stringLiteral:
            L10n.f("intent.cleanSafe.done", "Cleaned %1$d items, %2$@ freed.", outcome.itemCount, freed)))
    }
}

struct GetReclaimableSpaceIntent: AppIntent {
    static let title = LocalizedStringResource(
        "intent.reclaimable.title",
        defaultValue: "Get Reclaimable Space"
    )
    static let description = IntentDescription(
        LocalizedStringResource(
            "intent.reclaimable.description",
            defaultValue: "Scans all three cleanup levels and returns how much space Dusty could reclaim. Read-only: deletes nothing."
        )
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let result = await CleanerEngine().scan(sizingPolicy: .cached)
        let total = DiskSpaceMonitor.formatBytes(result.totalBytes)
        let safe = DiskSpaceMonitor.formatBytes(result.levelResults[.safe]?.totalBytes ?? 0)
        return .result(value: total, dialog: IntentDialog(stringLiteral:
            L10n.f("intent.reclaimable.result",
                   "%1$@ reclaimable (%2$@ of it safe to clean automatically).",
                   total, safe)))
    }
}

struct GetMemoryUsageIntent: AppIntent {
    static let title = LocalizedStringResource(
        "intent.memory.title",
        defaultValue: "Get Memory Usage"
    )
    static let description = IntentDescription(
        LocalizedStringResource(
            "intent.memory.description",
            defaultValue: "Returns how much memory is in use, the memory pressure, and the app holding the most. Read-only: quits nothing."
        )
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard let snapshot = MemoryMonitor().snapshot() else {
            return .result(value: "", dialog: IntentDialog(stringLiteral:
                L10n.t("intent.memory.failed", "Could not read memory statistics.")))
        }
        let used = MemorySnapshot.formatBytes(snapshot.usedBytes)
        let total = MemorySnapshot.formatBytes(snapshot.totalBytes)
        let own = getpid()
        let running = NSWorkspace.shared.runningApplications
        let appPIDs = Set(running.compactMap { $0.activationPolicy == .prohibited ? nil : $0.processIdentifier })
        let groups = await Task.detached(priority: .userInitiated) {
            AppMemoryGrouping.group(ProcessMemoryScanner.sample(), appPIDs: appPIDs, excludingPIDs: [own])
        }.value
        let top = groups.first { group in
            running.contains { $0.processIdentifier == group.leaderPID && MemoryModel.isQuittable($0) }
        }
        var message = L10n.f("intent.memory.result", "%1$@ of %2$@ in use. %3$@.",
                             used, total, snapshot.pressure.sentence)
        if let top {
            let name = running.first { $0.processIdentifier == top.leaderPID }?.localizedName ?? top.name
            message += " " + L10n.f("intent.memory.top", "%1$@ is using the most (%2$@).",
                                    name, MemorySnapshot.formatBytes(top.footprintBytes))
        }
        return .result(value: used, dialog: IntentDialog(stringLiteral: message))
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
            shortTitle: LocalizedStringResource("intent.cleanSafe.shortTitle", defaultValue: "Clean Safe"),
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: GetReclaimableSpaceIntent(),
            phrases: [
                "How much can \(.applicationName) clean",
                "Check reclaimable space in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("intent.reclaimable.shortTitle", defaultValue: "Reclaimable Space"),
            systemImageName: "internaldrive"
        )
        AppShortcut(
            intent: GetMemoryUsageIntent(),
            phrases: [
                "How much memory is in use in \(.applicationName)",
                "Check memory in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("intent.memory.shortTitle", defaultValue: "Memory Usage"),
            systemImageName: "memorychip"
        )
    }
}
