import SwiftUI
import CleanerEngine

struct LevelSectionView: View {
    let level: CleanupLevel
    let levelResult: LevelScanResult?
    let selectedBytes: Int64
    let isExpanded: Bool
    let isScanning: Bool
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
                .accessibilityLabel(L10n.f("level.a11y.label", "%@ cleanup level", level.title))
                .accessibilityValue(isExpanded
                                    ? L10n.t("level.a11y.expanded", "expanded")
                                    : L10n.t("level.a11y.collapsed", "collapsed"))
                .accessibilityHint(L10n.t("level.a11y.hint", "Shows every path found for this level"))

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
                    Text(L10n.t("level.clean", "Clean"))
                }
            }
            .frame(minWidth: 44, minHeight: 18)
        }
        .buttonStyle(DustyTintedButtonStyle(tint: levelColor, prominent: selectedBytes > 0 && canClean && !isCleaning))
        .disabled(levelResult == nil || selectedBytes == 0 || isCleaning || !canClean)
        .accessibilityLabel(L10n.f("level.a11y.cleanLabel", "Clean %@ items", level.title))
        .accessibilityValue(selectedBytes > 0
                            ? L10n.f("level.a11y.selected", "%@ selected", DiskSpaceMonitor.formatBytes(selectedBytes))
                            : L10n.t("level.a11y.nothingSelected", "nothing selected"))
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
            // No result yet: only say "Scanning…" when a scan is actually running.
            // After the user skips the welcome scan, nothing is in flight, so the
            // honest state is "not scanned" rather than a spinner that never resolves.
            Text(isScanning
                 ? L10n.t("panel.scan.scanning", "Scanning…")
                 : L10n.t("level.notScanned", "Not scanned yet. Run a scan to see items."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var levelBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(levelColor.opacity(0.15))
                .frame(width: 34, height: 34)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(levelColor.opacity(0.25), lineWidth: 1)
                .frame(width: 34, height: 34)
            Text("\(level.rawValue)")
                .font(.subheadline.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(levelColor)
        }
    }

    private var levelColor: Color { DustyTheme.levelColor(level.rawValue) }

    private var blockingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "app.dashed")
                .foregroundStyle(DustyTheme.warn)
            Text(blockingBannerText)
                .font(.caption)
                .foregroundStyle(DustyTheme.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DustyTheme.warn.opacity(0.10)))
        .padding(.bottom, 8)
    }

    private var blockingBannerText: String {
        L10n.f("level.blocking",
               "%2$@ are open, so their caches are skipped. Quit them to include them.",
               blockingApps.count,
               blockingApps.formatted(.list(type: .and)))
    }
}

struct TargetRowView: View {
    let targetResult: TargetScanResult
    let onTogglePath: (String, String) -> Void
    let onSelectAll: (String, Bool) -> Void
    /// Auto-cleaned targets start folded; manual-pick targets always show their items.
    @State private var showsPaths = false

    private var selectedInTarget: Int {
        targetResult.resolvedPaths.filter(\.isSelected).count
    }

    private var isManualPick: Bool { targetResult.target.needsUserSelection }
    private var pathsVisible: Bool { isManualPick || showsPaths }

    /// Largest first: the items worth reviewing are the ones holding the space.
    private var sortedPaths: [ResolvedPath] {
        targetResult.resolvedPaths.sorted { $0.estimatedBytes > $1.estimatedBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(targetResult.target.localizedName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if pathsVisible && !targetResult.resolvedPaths.isEmpty {
                    Text("\(selectedInTarget)/\(targetResult.resolvedPaths.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Button(L10n.t("common.all", "All")) { onSelectAll(targetResult.id, true) }
                        .buttonStyle(.link)
                        .font(.caption.weight(.medium))
                    Button(L10n.t("common.none", "None")) { onSelectAll(targetResult.id, false) }
                        .buttonStyle(.link)
                        .font(.caption.weight(.medium))
                }
                Text(DiskSpaceMonitor.formatBytes(targetResult.selectedBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let app = targetResult.target.requiresAppClosed {
                Label(L10n.f("target.skippedWhileOpen", "Skipped while %@ is open", app), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(DustyTheme.warn)
            }

            if pathsVisible {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedPaths) { path in
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
                        .padding(.vertical, 3)
                    }
                }
            }

            if !isManualPick && !targetResult.resolvedPaths.isEmpty {
                Button {
                    withAnimation(DustyTheme.revealSpring) { showsPaths.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(showsPaths ? 90 : 0))
                        Text(showsPaths
                             ? L10n.t("target.hideItems", "Hide items")
                             : L10n.f("target.showItems", "%d items · review or untick",
                                      targetResult.resolvedPaths.count))
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
                .accessibilityLabel(L10n.f(showsPaths ? "target.a11y.hideItems" : "target.a11y.showItems",
                                           showsPaths ? "Hide the %1$d items of %2$@" : "Show the %1$d items of %2$@",
                                           targetResult.resolvedPaths.count,
                                           targetResult.target.localizedName))
            }

            ForEach(targetResult.scanErrors, id: \.self) { err in
                Label(err, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(DustyTheme.danger)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
    }
}

private struct PathLabel: View {
    let path: ResolvedPath

    /// Rows older than this get an age hint next to the size; fresher ages are
    /// noise ("· 2 hours ago" would just churn).
    private static let ageHintAfterDays: TimeInterval = 30 * 86400

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(path.displayName)
                .font(.subheadline)
                .lineLimit(3)
                .textSelection(.enabled)
                .help(path.path)
            Text(subtitle)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }

    private var subtitle: String {
        let size = DiskSpaceMonitor.formatBytes(path.estimatedBytes)
        if let modified = path.lastModified,
           Date().timeIntervalSince(modified) > Self.ageHintAfterDays {
            return L10n.f("path.untouched", "%1$@ · untouched %2$@", size, RelativeTime.label(for: modified))
        }
        return size
    }
}
