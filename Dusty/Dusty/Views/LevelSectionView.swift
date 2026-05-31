import SwiftUI
import CleanerEngine

struct LevelSectionView: View {
    let level: CleanupLevel
    let levelResult: LevelScanResult?
    let selectedBytes: Int64
    let isExpanded: Bool
    let isCleaning: Bool
    let canClean: Bool
    let blockingApps: [String]
    let onToggleExpand: () -> Void
    let onClean: () -> Void
    let onTogglePath: (String, String) -> Void
    let onSelectAll: (String, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onToggleExpand) {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        levelBadge
                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.title)
                                .font(.subheadline.weight(.semibold))
                            Text(level.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if selectedBytes > 0 {
                    Text(DiskSpaceMonitor.formatBytes(selectedBytes))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                cleanButton
            }

            if isExpanded {
                detail.padding(.top, 10)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius)
                .fill(DustyTheme.cardBackground)
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        )
    }

    private var cleanButton: some View {
        Button(action: onClean) {
            Group {
                if isCleaning {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Clean").font(.caption.weight(.semibold))
                }
            }
            .frame(minWidth: 52)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(levelResult == nil || selectedBytes == 0 || isCleaning || !canClean)
    }

    @ViewBuilder private var detail: some View {
        if let result = levelResult {
            VStack(spacing: 0) {
                if !blockingApps.isEmpty {
                    blockingBanner
                }
                ForEach(result.targetResults) { targetResult in
                    if !targetResult.resolvedPaths.isEmpty || !targetResult.scanErrors.isEmpty {
                        TargetRowView(
                            targetResult: targetResult,
                            onTogglePath: onTogglePath,
                            onSelectAll: onSelectAll
                        )
                    }
                }
            }
        } else {
            Text("Scanning…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var levelBadge: some View {
        ZStack {
            Circle()
                .fill(levelColor.opacity(0.15))
                .frame(width: 28, height: 28)
            Text("\(level.rawValue)")
                .font(.caption.weight(.bold))
                .foregroundStyle(levelColor)
        }
    }

    private var levelColor: Color {
        switch level {
        case .safe: return .green
        case .developer: return .blue
        case .deep: return .orange
        }
    }

    private var blockingBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "app.dashed")
                .foregroundStyle(.orange)
            Text("\(blockingApps.joined(separator: ", ")) open, its cache is skipped. Quit to include it.")
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
        .padding(.bottom, 6)
    }
}

struct TargetRowView: View {
    let targetResult: TargetScanResult
    let onTogglePath: (String, String) -> Void
    let onSelectAll: (String, Bool) -> Void

    private var selectedInTarget: Int {
        targetResult.resolvedPaths.filter(\.isSelected).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(targetResult.target.displayName)
                    .font(.caption.weight(.semibold))
                Spacer()
                if targetResult.target.needsUserSelection && !targetResult.resolvedPaths.isEmpty {
                    Text("\(selectedInTarget)/\(targetResult.resolvedPaths.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Button("All") { onSelectAll(targetResult.id, true) }
                        .buttonStyle(.link)
                        .font(.caption2)
                    Button("None") { onSelectAll(targetResult.id, false) }
                        .buttonStyle(.link)
                        .font(.caption2)
                }
                Text(DiskSpaceMonitor.formatBytes(targetResult.selectedBytes))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let app = targetResult.target.requiresAppClosed {
                Label("Skipped while \(app) is open", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if targetResult.target.needsUserSelection {
                ForEach(targetResult.resolvedPaths) { path in
                    HStack(alignment: .top, spacing: 6) {
                        Toggle(isOn: Binding(
                            get: { path.isSelected },
                            set: { _ in onTogglePath(targetResult.id, path.id) }
                        )) {
                            PathLabel(path: path)
                        }
                        .toggleStyle(.checkbox)
                    }
                    .padding(.leading, 4)
                }
            } else if !targetResult.resolvedPaths.isEmpty {
                Text("\(targetResult.resolvedPaths.count) item\(targetResult.resolvedPaths.count == 1 ? "" : "s") · cleaned automatically")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }

            ForEach(targetResult.scanErrors, id: \.self) { err in
                Label(err, systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}

private struct PathLabel: View {
    let path: ResolvedPath

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(path.displayName)
                .font(.caption)
                .lineLimit(3)
                .textSelection(.enabled)
                .help(path.path)
            Text(DiskSpaceMonitor.formatBytes(path.estimatedBytes))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}
