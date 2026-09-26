import SwiftUI
import CleanerEngine

/// The top of the home screen: how full the disk is, how much of it Dusty can
/// give back, and the action that does it.
///
/// The storage bar draws the reclaimable space as its own colored slices at the
/// end of the used portion, one per level, so "what you could get back" reads
/// against "what you have" in one glance.
struct StorageHeroCard: View {
    @ObservedObject var viewModel: DustyViewModel
    @ObservedObject var settings: AppSettings

    private var free: Int64 { viewModel.freeSpaceBytes }
    private var total: Int64 { viewModel.totalSpaceBytes }
    private var used: Int64 { max(0, total - free) }

    private var health: DustyTheme.DiskHealth {
        total > 0 ? DustyTheme.DiskHealth(freeRatio: viewModel.freeSpaceRatio) : .healthy
    }

    /// Reclaimable bytes per level, capped so the slices never claim more than
    /// the used portion (Trash and snapshots can make the sums disagree).
    private var reclaimableByLevel: [(level: CleanupLevel, bytes: Int64)] {
        var budget = used
        return CleanupLevel.allCases.map { level in
            let bytes = min(budget, viewModel.reclaimableBytes(for: level))
            budget -= bytes
            return (level: level, bytes: bytes)
        }
    }

    private var segments: [CapacityBar.Segment] {
        guard total > 0 else { return [] }
        let share = { (bytes: Int64) in Double(bytes) / Double(total) }
        let reclaimable = reclaimableByLevel
        let reclaimableTotal = reclaimable.reduce(Int64(0)) { $0 + $1.bytes }
        var result = [CapacityBar.Segment(id: "used", fraction: share(used - reclaimableTotal), color: DustyTheme.usedSpace)]
        for item in reclaimable {
            result.append(CapacityBar.Segment(id: "level-\(item.level.rawValue)", fraction: share(item.bytes), color: item.level.tint))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            storage
                .padding(16)
            Hairline()
            status
                .padding(16)
        }
        .dustyCard()
    }

    // MARK: - Storage

    private var storage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 11, weight: .semibold))
                Text(viewModel.volumeName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                StatusPill(text: health.label, tint: health.tint)
            }
            .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                BigBytes(bytes: free, size: 34)
                Text(L10n.f("hero.availableOf", "available of %@", Bytes.format(total)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.t("header.a11y.label", "Disk space"))
            .accessibilityValue(L10n.f("header.a11y.value", "%1$@ free of %2$@, %3$d percent used",
                                       Bytes.format(free), Bytes.format(total),
                                       total > 0 ? Int((1 - viewModel.freeSpaceRatio) * 100) : 0))

            CapacityBar(segments: segments, height: 10)
                .accessibilityHidden(true)

            legend
        }
    }

    private var legend: some View {
        let reclaimable = viewModel.hasScannedOnce ? viewModel.totalReclaimableBytes : 0
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                LegendItem(color: DustyTheme.usedSpace, label: L10n.t("hero.legend.used", "Used"), value: Bytes.format(used))
                if reclaimable > 0 {
                    reclaimableLegend(value: Bytes.format(reclaimable))
                }
                LegendItem(color: DustyTheme.inset, label: L10n.t("hero.legend.free", "Free"), value: Bytes.format(free))
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                LegendItem(color: DustyTheme.usedSpace, label: L10n.t("hero.legend.used", "Used"), value: Bytes.format(used))
                if reclaimable > 0 {
                    reclaimableLegend(value: Bytes.format(reclaimable))
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// The reclaimable key is a tiny three-level swatch, matching the slices.
    private func reclaimableLegend(value: String) -> some View {
        HStack(spacing: 5) {
            HStack(spacing: 0) {
                ForEach(CleanupLevel.allCases) { level in
                    Rectangle().fill(level.tint).frame(width: 3, height: 8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            Text(L10n.t("hero.legend.cleanable", "Cleanable"))
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Status and action

    @ViewBuilder private var status: some View {
        if viewModel.isScanning {
            scanning
        } else if !viewModel.hasScannedOnce {
            notScanned
        } else if viewModel.hasReclaimableSpace {
            reclaimable
        } else {
            allClean
        }
    }

    private var scanning: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Spinner(tint: DustyTheme.accent, size: 13)
                Text(L10n.t("panel.scan.scanning", "Scanning…"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let progress = viewModel.scanProgress {
                    Text(L10n.f("hero.scan.count", "%1$d of %2$d", progress.completed, progress.total))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressCapsule(fraction: viewModel.scanProgress?.fraction ?? 0)
            HStack {
                Text(viewModel.scanProgress?.currentTargetName ?? L10n.t("panel.scan.starting", "Starting…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(L10n.t("common.cancel", "Cancel")) { viewModel.cancelScan() }
                    .buttonStyle(DustyLinkButtonStyle())
                    .font(.caption.weight(.semibold))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var notScanned: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("hero.notScanned.title", "See what you can reclaim"))
                    .font(.subheadline.weight(.semibold))
                Text(L10n.t("hero.notScanned.body", "A scan measures caches and junk, path by path. It never deletes anything."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                viewModel.startScan(settings: settings)
            } label: {
                Label(L10n.t("panel.scan.start", "Scan disk"), systemImage: "magnifyingglass")
            }
            .buttonStyle(DustyPrimaryButtonStyle())
            .keyboardShortcut("r", modifiers: .command)
            .disabled(viewModel.isCleaning)
        }
    }

    private var reclaimable: some View {
        let safeBytes = viewModel.cleanableBytes(for: .safe)
        let isCleaningSafe = viewModel.isCleaning && viewModel.cleaningLevel == .safe
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        BigBytes(bytes: viewModel.totalReclaimableBytes, size: 22)
                        Text(L10n.t("hero.canBeCleaned", "can be cleaned"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let scannedAt = viewModel.scanResult?.scannedAt {
                        // Relative on purpose: a bare clock time reads as today even when
                        // the scan is days old, and this panel can sit unopened for weeks.
                        Text(L10n.f("panel.scan.lastScan", "Last scan: %@", RelativeTime.label(for: scannedAt)))
                            .font(.caption)
                            .foregroundStyle(DustyTheme.faint)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer()
                rescanButton
            }

            if safeBytes > 0 || isCleaningSafe {
                Button {
                    viewModel.cleanSafe()
                } label: {
                    HStack(spacing: 7) {
                        if isCleaningSafe {
                            Spinner(tint: .white, size: 13)
                            Text(L10n.t("hero.cleaning", "Cleaning…"))
                        } else {
                            Image(systemName: "sparkles")
                            Text(L10n.f("reclaim.cleanSafe", "Clean Safe · %@", Bytes.format(safeBytes)))
                                .monospacedDigit()
                        }
                    }
                }
                .buttonStyle(DustyPrimaryButtonStyle())
                .disabled(isCleaningSafe || viewModel.isCleaning || !viewModel.canClean(level: .safe))

                if !settings.dryRunDefault && !isCleaningSafe {
                    Text(L10n.f("hero.afterClean", "You'll have %@ free afterwards",
                                Bytes.format(viewModel.projectedFreeBytes(afterReclaiming: safeBytes))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            } else if let level = viewModel.largestLevelWithItems {
                // Nothing Safe to clean, but other levels hold space: point there
                // rather than showing a dead button.
                Button {
                    viewModel.open(.level(level))
                } label: {
                    HStack(spacing: 6) {
                        Text(L10n.f("hero.review", "Review %@ items", level.name))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                }
                .buttonStyle(DustySecondaryButtonStyle(fullWidth: true))
            }
        }
    }

    private var allClean: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(DustyTheme.success.opacity(0.14))
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DustyTheme.success)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("panel.allClean.title", "All clean"))
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.scanResult.map {
                        L10n.f("panel.allClean.bodyChecked",
                               "Nothing reclaimable (checked %@). Dusty keeps watching in the background.",
                               RelativeTime.label(for: $0.scannedAt))
                     } ?? L10n.t("panel.allClean.body",
                                 "Nothing reclaimable right now. Dusty keeps watching in the background."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            rescanButton
        }
    }

    private var rescanButton: some View {
        Button {
            viewModel.startScan(settings: settings)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(DustyIconButtonStyle(size: 30))
        .keyboardShortcut("r", modifiers: .command)
        .disabled(viewModel.isScanning || viewModel.isCleaning)
        .help(L10n.t("hero.rescanHelp", "Rescan (⌘R)"))
        .accessibilityLabel(L10n.t("panel.scan.rescan", "Rescan"))
    }
}

/// A byte count set as a headline: the number large and rounded, the unit
/// smaller beside it ("182.4" + "GB"), so the figure is what the eye lands on.
struct BigBytes: View {
    let bytes: Int64
    var size: CGFloat = 34
    /// Binary units, for RAM.
    var memory = false

    var body: some View {
        let parts = Bytes.split(bytes, memory: memory)
        HStack(alignment: .firstTextBaseline, spacing: size * 0.1) {
            Text(parts.value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: bytes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(memory ? Bytes.memory(bytes) : Bytes.format(bytes))
    }
}

extension Bytes {
    /// "182,4 GB" -> ("182,4", "GB"). Splits at the last space the formatter put
    /// in (regular or no-break), so every locale's unit survives intact.
    static func split(_ bytes: Int64, memory: Bool = false) -> (value: String, unit: String) {
        let formatted = memory ? Bytes.memory(bytes) : Bytes.format(bytes)
        guard let space = formatted.lastIndex(where: { $0 == " " || $0 == "\u{00A0}" || $0 == "\u{202F}" }) else {
            return (formatted, "")
        }
        return (String(formatted[..<space]), String(formatted[formatted.index(after: space)...]))
    }
}
