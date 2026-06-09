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

    private var accent: Color { dryRun ? DustyTheme.gold : .red }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            pathList
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 418, height: min(560, CGFloat(240 + paths.count * 27)))
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
            Image(systemName: dryRun ? "eye.circle.fill" : "trash.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(accent)
                .symbolRenderingMode(.hierarchical)

            Text(dryRun ? "Preview Cleanup" : "Confirm Cleanup")
                .font(.title2.weight(.bold))

            Text("\(paths.count) item\(paths.count == 1 ? "" : "s") · \(DiskSpaceMonitor.formatBytes(bytes))")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            VStack(spacing: 6) {
                if !skippedApps.isEmpty {
                    Label("Skipping \(skippedApps.joined(separator: ", ")) cache, app is open", systemImage: "app.dashed")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                if dryRun {
                    Label("Dry run: nothing will be deleted", systemImage: "eye")
                        .font(.footnote)
                        .foregroundStyle(.blue)
                }
                if !dryRun {
                    Label("Recoverable for a few seconds via Undo", systemImage: "arrow.uturn.backward")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if moveToTrash {
                    Label("Items stay in the Trash until you empty it", systemImage: "trash")
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
                            .foregroundStyle(.red.opacity(0.75))
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
                            Button("Reveal in Finder") {
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
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
            Spacer()
            Button(action: onConfirm) {
                Text(dryRun ? "Run Dry Run" : "Delete")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 80)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .controlSize(.large)
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
        case .trashed: return "Moved to Trash"
        case .undoable: return "Cleaned, recoverable"
        case .reclaimed: return "Cleanup complete"
        }
    }
    private var tint: Color { style == .trashed ? .orange : DustyTheme.diskColor(ratio: 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: style == .trashed ? "trash.fill" : "checkmark.circle.fill")
                    .foregroundStyle(tint)
                    .font(.headline)
                Spacer()
                if style == .undoable, let onUndo {
                    Button("Undo", action: onUndo)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
            }

            HStack(spacing: 5) {
                Text(DiskSpaceMonitor.formatBytes(result.bytesFreed))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(tint)
                Text(style == .trashed ? "moved" : "cleaned")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            switch style {
            case .trashed:
                Text("Empty Trash to reclaim this space.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .undoable:
                Text("Undo is available for a few seconds.")
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
                    Label("\(result.skippedPaths.count) skipped, tap to \(showSkipped ? "hide" : "show")", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)

                if showSkipped {
                    ForEach(Array(result.skippedPaths.enumerated()), id: \.offset) { _, item in
                        Text("\(item.path): \(item.reason)")
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
                .foregroundStyle(.orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text("Full Disk Access recommended")
                    .font(.subheadline.weight(.semibold))
                Text("Grant access in System Settings to scan system logs and protected caches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open", action: onOpenSettings)
                .controlSize(.regular)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: Updater
    @Environment(\.dismiss) private var dismiss
    var onRefreshIntervalChanged: (TimeInterval) -> Void
    var onDone: (() -> Void)? = nil

    private func close() { if let onDone { onDone() } else { dismiss() } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title3.weight(.bold))
                Spacer()
                Button("Done", action: close)
                    .font(.body.weight(.semibold))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider().opacity(0.5)

            Form {
                Section("General") {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    Toggle("Show free space as a percentage", isOn: $settings.menuBarShowsPercentage)
                }

                Section("Refresh") {
                    Stepper(
                        "Menu bar interval: \(Int(settings.refreshIntervalSeconds))s",
                        value: $settings.refreshIntervalSeconds,
                        in: 10...300,
                        step: 10
                    )
                    .onChange(of: settings.refreshIntervalSeconds) { newValue in
                        onRefreshIntervalChanged(newValue)
                    }
                }

                Section("Auto scan") {
                    Toggle("Scan in the background", isOn: $settings.autoScanEnabled)
                    Stepper(
                        "Every \(settings.autoScanIntervalHours) h",
                        value: $settings.autoScanIntervalHours,
                        in: 1...24,
                        step: 1
                    )
                    .disabled(!settings.autoScanEnabled)
                    Text("Quietly keeps the menu bar figure current. Never deletes anything on its own.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))
                    Toggle("Download and install automatically", isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.automaticallyDownloadsUpdates = $0 }
                    ))
                    HStack {
                        Button("Check for Updates Now") { updater.checkForUpdates() }
                            .disabled(!updater.canCheckForUpdates)
                        Spacer()
                        Text("v\(Bundle.main.shortVersion) (\(Bundle.main.buildVersion))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Section("Cleanup defaults") {
                    Toggle("Dry run by default", isOn: $settings.dryRunDefault)
                    Toggle("Keep Developer & Deep items in Trash", isOn: $settings.moveToTrashDefault)
                    Stepper(
                        "System log age: \(settings.logAgeThresholdDays) days",
                        value: $settings.logAgeThresholdDays,
                        in: 7...365,
                        step: 7
                    )
                }

                Section("Safety") {
                    Text("Dusty uses a strict allowlist: only paths in CleanupTargetRegistry can be deleted, and never through a symlink. No sudo, no SIP-protected paths. The one system folder it can touch, /Library/Logs/DiagnosticReports, is opt-in and age-filtered.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Deletion log: ~/Library/Application Support/Dusty/")
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
