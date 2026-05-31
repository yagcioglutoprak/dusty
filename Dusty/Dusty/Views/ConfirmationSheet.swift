import SwiftUI
import AppKit
import CleanerEngine

struct ConfirmationSheet: View {
    let level: CleanupLevel
    let paths: [ResolvedPath]
    let bytes: Int64
    let dryRun: Bool
    let moveToTrash: Bool
    let skippedApps: [String]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pathList
            Divider()
            footer
        }
        .frame(width: 480, height: min(520, CGFloat(160 + paths.count * 28)))
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: dryRun ? "eye.circle.fill" : "trash.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(dryRun ? .blue : .orange)
                .symbolRenderingMode(.hierarchical)

            Text("Confirm Cleanup")
                .font(.title3.weight(.semibold))

            Text("\(paths.count) item\(paths.count == 1 ? "" : "s") · \(DiskSpaceMonitor.formatBytes(bytes))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if !skippedApps.isEmpty {
                Label("Skipping \(skippedApps.joined(separator: ", ")) cache, app is open", systemImage: "app.dashed")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            if dryRun {
                Label("Dry run: nothing will be deleted", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            if moveToTrash {
                Label("Items will be moved to Trash", systemImage: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var pathList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(paths) { path in
                    HStack(alignment: .top) {
                        Image(systemName: "minus.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.7))
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(path.displayName)
                                .font(.caption)
                                .lineLimit(2)
                                .textSelection(.enabled)
                            Text(path.path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Text(DiskSpaceMonitor.formatBytes(path.estimatedBytes))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .contextMenu {
                        if path.path.hasPrefix("/") {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path.path)])
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(dryRun ? "Run Dry Run" : "Delete", action: onConfirm)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
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
    private var tint: Color { style == .trashed ? .orange : .green }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: style == .trashed ? "trash.fill" : "checkmark.circle.fill")
                    .foregroundStyle(tint)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if style == .undoable, let onUndo {
                    Button("Undo", action: onUndo)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            HStack(spacing: 4) {
                Text(DiskSpaceMonitor.formatBytes(result.bytesFreed))
                    .fontWeight(.medium)
                Text(style == .trashed ? "moved" : "cleaned")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            switch style {
            case .trashed:
                Text("Empty Trash to reclaim this space.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .undoable:
                Text("Recoverable for a few seconds, then permanently removed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .reclaimed:
                HStack(spacing: 6) {
                    Text(DiskSpaceMonitor.formatBytes(result.freeSpaceBefore))
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Text(DiskSpaceMonitor.formatBytes(result.freeSpaceAfter))
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            if !result.skippedPaths.isEmpty {
                Button {
                    withAnimation { showSkipped.toggle() }
                } label: {
                    Label("\(result.skippedPaths.count) skipped, tap to \(showSkipped ? "hide" : "show")", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)

                if showSkipped {
                    ForEach(Array(result.skippedPaths.enumerated()), id: \.offset) { _, item in
                        Text("\(item.path): \(item.reason)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius)
                .fill(Color.green.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: DustyTheme.cornerRadius).stroke(Color.green.opacity(0.2)))
        )
    }
}

struct FullDiskAccessBanner: View {
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access recommended")
                    .font(.caption.weight(.semibold))
                Text("Grant access in System Settings to scan system logs and protected caches.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings", action: onOpenSettings)
                .controlSize(.small)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius)
                .fill(Color.orange.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: DustyTheme.cornerRadius).stroke(Color.orange.opacity(0.2)))
        )
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    var onRefreshIntervalChanged: (TimeInterval) -> Void
    var onDone: (() -> Void)? = nil

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
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

            Section("Cleanup defaults") {
                Toggle("Dry run by default", isOn: $settings.dryRunDefault)
                Toggle("Move to Trash (levels 2 & 3)", isOn: $settings.moveToTrashDefault)
                Stepper(
                    "System log age: \(settings.logAgeThresholdDays) days",
                    value: $settings.logAgeThresholdDays,
                    in: 7...365,
                    step: 7
                )
            }

            Section("Safety") {
                Text("Dusty uses a strict allowlist. Only paths in CleanupTargetRegistry can be deleted. No sudo, no system paths, no symlinks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Deletion log: ~/Library/Application Support/Dusty/")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 400)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { if let onDone { onDone() } else { dismiss() } }
            }
        }
    }
}
