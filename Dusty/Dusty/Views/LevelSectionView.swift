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
            HStack(spacing: 12) {
                Button(action: onToggleExpand) {
                    HStack(spacing: 12) {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        levelBadge
                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.title)
                                .font(.body.weight(.semibold))
                            Text(level.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(level.title) cleanup level")
                .accessibilityValue(isExpanded ? "expanded" : "collapsed")
                .accessibilityHint("Shows every path found for this level")

                if selectedBytes > 0 {
                    Text(DiskSpaceMonitor.formatBytes(selectedBytes))
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                cleanButton
            }

            if isExpanded {
                detail.padding(.top, 12)
            }
        }
        .padding(14)
        .dustyCard()
    }

    private var cleanButton: some View {
        Button(action: onClean) {
            Group {
                if isCleaning {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Clean").font(.subheadline.weight(.bold))
                }
            }
            .frame(minWidth: 58, minHeight: 18)
        }
        .buttonStyle(.borderedProminent)
        .tint(levelColor)
        .controlSize(.regular)
        .disabled(levelResult == nil || selectedBytes == 0 || isCleaning || !canClean)
        .accessibilityLabel("Clean \(level.title) items")
        .accessibilityValue(selectedBytes > 0 ? "\(DiskSpaceMonitor.formatBytes(selectedBytes)) selected" : "nothing selected")
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var levelBadge: some View {
        ZStack {
            Circle()
                .fill(levelColor.opacity(0.18))
                .frame(width: 34, height: 34)
            Text("\(level.rawValue)")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(levelColor)
        }
    }

    private var levelColor: Color { DustyTheme.levelColor(level.rawValue) }

    private var blockingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "app.dashed")
                .foregroundStyle(.orange)
            Text("\(blockingApps.joined(separator: ", ")) open, its cache is skipped. Quit to include it.")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
        .padding(.bottom, 8)
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
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(targetResult.target.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if targetResult.target.needsUserSelection && !targetResult.resolvedPaths.isEmpty {
                    Text("\(selectedInTarget)/\(targetResult.resolvedPaths.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Button("All") { onSelectAll(targetResult.id, true) }
                        .buttonStyle(.link)
                        .font(.caption.weight(.medium))
                    Button("None") { onSelectAll(targetResult.id, false) }
                        .buttonStyle(.link)
                        .font(.caption.weight(.medium))
                }
                Text(DiskSpaceMonitor.formatBytes(targetResult.selectedBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let app = targetResult.target.requiresAppClosed {
                Label("Skipped while \(app) is open", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
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
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }

            ForEach(targetResult.scanErrors, id: \.self) { err in
                Label(err, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
    }
}

private struct PathLabel: View {
    let path: ResolvedPath

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(path.displayName)
                .font(.subheadline)
                .lineLimit(3)
                .textSelection(.enabled)
                .help(path.path)
            Text(DiskSpaceMonitor.formatBytes(path.estimatedBytes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}
