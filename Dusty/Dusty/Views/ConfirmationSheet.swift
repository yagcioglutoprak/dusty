import SwiftUI
import AppKit
import CleanerEngine

/// In-panel confirmation. Presented as an overlay (never a sheet) so the
/// MenuBarExtra window keeps focus and stays open while the user decides.
struct ConfirmationCard: View {
    let level: CleanupLevel
    let paths: [ResolvedPath]
    let bytes: Int64
    let dryRun: Bool
    let moveToTrash: Bool
    let skippedApps: [String]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var accent: Color { dryRun ? DustyTheme.gold : DustyTheme.danger }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            pathList
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 418, height: min(560, CGFloat(262 + paths.count * 27)))
        .background(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: DustyTheme.overlayShadow, radius: 28, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                .stroke(DustyTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous))
        .padding(20)
    }

    private var header: some View {
        VStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 64, height: 64)
                Circle()
                    .strokeBorder(accent.opacity(0.22), lineWidth: 1)
                    .frame(width: 64, height: 64)
                Image(systemName: dryRun ? "eye.fill" : "trash.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(accent)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)

            Text(dryRun
                 ? L10n.t("confirm.title.dryRun", "Preview Cleanup")
                 : L10n.t("confirm.title", "Confirm Cleanup"))
                .font(.title2.weight(.bold))

            Text(L10n.f("confirm.itemCount", "%1$d items · %2$@",
                        paths.count, DiskSpaceMonitor.formatBytes(bytes)))
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            VStack(spacing: 6) {
                if !skippedApps.isEmpty {
                    Label(L10n.f("confirm.skippingApps", "Skipping %@ cache, app is open",
                                 skippedApps.formatted(.list(type: .and))), systemImage: "app.dashed")
                        .font(.footnote)
                        .foregroundStyle(DustyTheme.warn)
                        .multilineTextAlignment(.center)
                }
                if dryRun {
                    Label(L10n.t("confirm.dryRunNote", "Dry run: nothing will be deleted"), systemImage: "eye")
                        .font(.footnote)
                        .foregroundStyle(DustyTheme.info)
                }
                if !dryRun {
                    Label(L10n.t("confirm.undoNote", "Recoverable for a few seconds via Undo"), systemImage: "arrow.uturn.backward")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if moveToTrash {
                    Label(L10n.t("confirm.trashNote", "Items stay in the Trash until you empty it"), systemImage: "trash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(22)
    }

    private var pathList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 5) {
                ForEach(paths) { path in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "minus.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(DustyTheme.danger.opacity(0.75))
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(path.displayName)
                                .font(.subheadline)
                                .lineLimit(2)
                                .textSelection(.enabled)
                            Text(path.path)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Text(DiskSpaceMonitor.formatBytes(path.estimatedBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        if path.path.hasPrefix("/") {
                            Button(L10n.t("common.revealInFinder", "Reveal in Finder")) {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path.path)])
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(L10n.t("common.cancel", "Cancel"), action: onCancel)
                .buttonStyle(DustyGhostButtonStyle(fullWidth: false))
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(action: onConfirm) {
                Text(dryRun
                     ? L10n.t("confirm.action.dryRun", "Run Dry Run")
                     : L10n.t("confirm.action.delete", "Delete"))
                    .frame(minWidth: 86)
            }
            .buttonStyle(DustyTintedButtonStyle(tint: accent, prominent: true,
                                                prominentLabel: dryRun ? DustyTheme.onGold : .white))
            .keyboardShortcut(.defaultAction)
        }
        .padding(18)
    }
}

struct DeletionResultBanner: View {
    let result: DeletionResult
    var style: ResultBannerStyle = .reclaimed
    var onUndo: (() -> Void)? = nil
    @State private var showSkipped = false

    private var title: String {
        switch style {
        case .trashed: return L10n.t("result.title.trashed", "Moved to Trash")
        case .undoable: return L10n.t("result.title.undoable", "Cleaned, recoverable")
        case .reclaimed: return L10n.t("result.title.reclaimed", "Cleanup complete")
        }
    }
    private var tint: Color { style == .trashed ? DustyTheme.warn : DustyTheme.success }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: style == .trashed ? "trash.fill" : "checkmark.circle.fill")
                    .foregroundStyle(tint)
                    .font(.headline)
                Spacer()
                if style == .undoable, let onUndo {
                    Button(L10n.t("common.undo", "Undo"), action: onUndo)
                        .buttonStyle(DustyTintedButtonStyle(tint: tint))
                }
            }

            HStack(spacing: 5) {
                Text(DiskSpaceMonitor.formatBytes(result.bytesFreed))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(tint)
                Text(style == .trashed
                     ? L10n.t("result.moved", "moved")
                     : L10n.t("result.cleaned", "cleaned"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            switch style {
            case .trashed:
                Text(L10n.t("result.body.trashed", "Empty Trash to reclaim this space."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .undoable:
                Text(L10n.t("result.body.undoable", "Undo is available for a few seconds."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .reclaimed:
                HStack(spacing: 7) {
                    Text(DiskSpaceMonitor.formatBytes(result.freeSpaceBefore))
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                    Text(DiskSpaceMonitor.formatBytes(result.freeSpaceAfter))
                        .fontWeight(.bold)
                        .foregroundStyle(tint)
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            if !result.skippedPaths.isEmpty {
                Button {
                    withAnimation { showSkipped.toggle() }
                } label: {
                    Label(L10n.f(showSkipped ? "result.skipped.hide" : "result.skipped.show",
                                 showSkipped ? "%d skipped, tap to hide" : "%d skipped, tap to show",
                                 result.skippedPaths.count), systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(DustyTheme.warn)
                }
                .buttonStyle(.plain)

                if showSkipped {
                    ForEach(Array(result.skippedPaths.enumerated()), id: \.offset) { _, item in
                        Text(L10n.f("result.skippedLine", "%1$@: %2$@", item.path, item.reason))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                .fill(tint.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

struct FullDiskAccessBanner: View {
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(DustyTheme.warn)
                .font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("fda.title", "Full Disk Access recommended"))
                    .font(.subheadline.weight(.semibold))
                Text(L10n.t("fda.body", "Grant access in System Settings to scan system logs and protected caches."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(L10n.t("common.open", "Open"), action: onOpenSettings)
                .buttonStyle(DustyTintedButtonStyle(tint: DustyTheme.warn))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                .fill(DustyTheme.warn.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                        .stroke(DustyTheme.warn.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: Updater
    @ObservedObject private var statsStore = CleanStatsStore.shared
    @Environment(\.dismiss) private var dismiss
    var onRefreshIntervalChanged: (TimeInterval) -> Void
    var onDone: (() -> Void)? = nil

    /// Seeded from what the app launched with, so switching the picker leaves a
    /// visible "restart to apply" affordance instead of silently doing nothing.
    @State private var language = AppLanguage.current

    private func close() { if let onDone { onDone() } else { dismiss() } }

    private var autoCleanCaption: String {
        let scope = settings.autoCleanIncludesDeveloper
            ? L10n.t("settings.autoCleanScope.developer",
                     "Safe caches plus Developer caches (DerivedData, package managers)")
            : L10n.t("settings.autoCleanScope.safe", "Safe-level caches only")
        return L10n.f(
            "settings.autoCleanCaption",
            "%@. Apps that are open are skipped, a notification reports what was reclaimed, and every path lands in the deletion log.",
            scope
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("common.settings", "Settings"))
                    .font(.title3.weight(.bold))
                Spacer()
                Button(L10n.t("common.done", "Done"), action: close)
                    .font(.body.weight(.semibold))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().opacity(0.5)

            Form {
                Section(L10n.t("settings.section.general", "General")) {
                    Toggle(L10n.t("settings.launchAtLogin", "Launch at login"), isOn: $settings.launchAtLogin)
                    Toggle(L10n.t("settings.menuBarPercentage", "Show free space as a percentage"),
                           isOn: $settings.menuBarShowsPercentage)
                    Toggle(L10n.t("settings.menuBarReclaimable", "Show reclaimable space in the menu bar"),
                           isOn: $settings.menuBarShowsReclaimable)
                }

                Section(L10n.t("settings.section.language", "Language")) {
                    Picker(L10n.t("settings.language", "Panel language"), selection: $language) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .onChange(of: language) { newValue in AppLanguage.apply(newValue) }

                    // Bundle localizations are chosen once, at launch. Rather than
                    // pretend otherwise, say so and offer the restart.
                    if language != AppLanguage.launchLanguage {
                        HStack(alignment: .firstTextBaseline) {
                            Text(L10n.t("settings.language.restartNote",
                                        "Dusty has to restart to change language."))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Button(L10n.t("settings.language.restart", "Restart Dusty")) {
                                AppLanguage.relaunch()
                            }
                        }
                    }
                }

                Section(L10n.t("settings.section.refresh", "Refresh")) {
                    Stepper(
                        L10n.f("settings.refreshInterval", "Menu bar interval: %ds",
                               Int(settings.refreshIntervalSeconds)),
                        value: $settings.refreshIntervalSeconds,
                        in: 10...300,
                        step: 10
                    )
                    .onChange(of: settings.refreshIntervalSeconds) { newValue in
                        onRefreshIntervalChanged(newValue)
                    }
                }

                Section(L10n.t("settings.section.autoScan", "Auto scan")) {
                    Toggle(L10n.t("settings.autoScanEnabled", "Scan in the background"),
                           isOn: $settings.autoScanEnabled)
                    Stepper(
                        L10n.f("settings.autoScanInterval", "Every %d hours", settings.autoScanIntervalHours),
                        value: $settings.autoScanIntervalHours,
                        in: 1...24,
                        step: 1
                    )
                    .disabled(!settings.autoScanEnabled)
                    Text(L10n.t("settings.autoScanCaption",
                                "Quietly keeps the menu bar figure current. Never deletes anything on its own."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Section(L10n.t("settings.section.autoClean", "Auto clean")) {
                    Toggle(L10n.t("settings.autoCleanEnabled", "Clean Safe items on a schedule"),
                           isOn: $settings.autoCleanEnabled)
                        .disabled(settings.dryRunDefault)
                    Picker(L10n.t("settings.autoCleanFrequency", "Frequency"),
                           selection: $settings.autoCleanFrequencyDays) {
                        Text(L10n.t("settings.frequency.daily", "Every day")).tag(1)
                        Text(L10n.t("settings.frequency.weekly", "Every week")).tag(7)
                        Text(L10n.t("settings.frequency.biweekly", "Every two weeks")).tag(14)
                    }
                    .disabled(!settings.autoCleanEnabled || settings.dryRunDefault)
                    Toggle(L10n.t("settings.autoCleanLowDisk", "Also clean when free space runs low"),
                           isOn: $settings.autoCleanWhenLowDisk)
                        .disabled(settings.dryRunDefault)
                    Stepper(
                        L10n.f("settings.autoCleanThreshold", "Below %d GB free",
                               settings.autoCleanLowDiskThresholdGB),
                        value: $settings.autoCleanLowDiskThresholdGB,
                        in: 5...100,
                        step: 5
                    )
                    .disabled(!settings.autoCleanWhenLowDisk || settings.dryRunDefault)
                    Toggle(L10n.t("settings.autoCleanDeveloper", "Include Developer caches"),
                           isOn: $settings.autoCleanIncludesDeveloper)
                        .disabled((!settings.autoCleanEnabled && !settings.autoCleanWhenLowDisk) || settings.dryRunDefault)
                    Text(settings.dryRunDefault
                         ? L10n.t("settings.autoCleanDryRunNote",
                                  "Off while dry run is the default: nothing is deleted unattended.")
                         : autoCleanCaption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if statsStore.cleanCount > 0 {
                    Section(L10n.t("settings.section.stats", "Statistics")) {
                        LabeledContent(L10n.t("settings.stats.lifetime", "Reclaimed all-time")) {
                            Text(DiskSpaceMonitor.formatBytes(statsStore.lifetimeBytes))
                                .monospacedDigit()
                        }
                        LabeledContent(L10n.t("settings.stats.cleans", "Cleans")) {
                            Text("\(statsStore.cleanCount)")
                                .monospacedDigit()
                        }
                        if let since = statsStore.firstCleanAt {
                            LabeledContent(L10n.t("settings.stats.since", "Since")) {
                                Text(since, format: .dateTime.day().month().year())
                            }
                        }
                        if !statsStore.recent.isEmpty {
                            DisclosureGroup(L10n.t("settings.stats.recent", "Recent cleans")) {
                                ForEach(statsStore.recent) { record in
                                    HStack {
                                        Text(RelativeTime.label(for: record.date))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(L10n.f("settings.stats.level", "Level %d", record.level))
                                            .foregroundStyle(.tertiary)
                                        Text(DiskSpaceMonitor.formatBytes(record.bytes))
                                            .monospacedDigit()
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }

                Section(L10n.t("settings.section.updates", "Updates")) {
                    Toggle(L10n.t("settings.updates.auto", "Check for updates automatically"), isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))
                    Toggle(L10n.t("settings.updates.autoInstall", "Download and install automatically"), isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.automaticallyDownloadsUpdates = $0 }
                    ))
                    HStack {
                        Button(L10n.t("settings.updates.checkNow", "Check for Updates Now")) {
                            updater.checkForUpdates()
                        }
                        .disabled(!updater.canCheckForUpdates)
                        Spacer()
                        Text("v\(Bundle.main.shortVersion) (\(Bundle.main.buildVersion))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Section(L10n.t("settings.section.cleanupDefaults", "Cleanup defaults")) {
                    Toggle(L10n.t("settings.dryRunDefault", "Dry run by default"), isOn: $settings.dryRunDefault)
                    Toggle(L10n.t("settings.moveToTrash", "Keep Developer & Deep items in Trash"),
                           isOn: $settings.moveToTrashDefault)
                    Stepper(
                        L10n.f("settings.logAge", "System log age: %d days", settings.logAgeThresholdDays),
                        value: $settings.logAgeThresholdDays,
                        in: 7...365,
                        step: 7
                    )
                }

                Section(L10n.t("settings.section.safety", "Safety")) {
                    Text(L10n.t("settings.safety.body", "Dusty uses a strict allowlist: only paths in CleanupTargetRegistry can be deleted, and never through a symlink. No sudo, no SIP-protected paths. The one system folder it can touch, /Library/Logs/DiagnosticReports, is opt-in and age-filtered."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(L10n.t("settings.safety.logPath", "Deletion log: ~/Library/Application Support/Dusty/"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 418, height: 480)
        .background(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: DustyTheme.overlayShadow, radius: 28, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                .stroke(DustyTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous))
        .padding(20)
    }
}
