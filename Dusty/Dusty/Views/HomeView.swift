import SwiftUI
import AppKit
import CleanerEngine

/// The root screen: the disk at a glance, the one-tap Safe clean, memory with
/// its own one-tap Free up, the three levels to drill into, and what the scan
/// noticed.
struct HomeView: View {
    @ObservedObject var viewModel: DustyViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: Updater
    @ObservedObject var memory: MemoryModel
    @ObservedObject private var stats = CleanStatsStore.shared
    @State private var fdaDismissed = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StorageHeroCard(viewModel: viewModel, settings: settings)
                    banners
                    MemoryCard(
                        memory: memory,
                        onOpen: { viewModel.open(.memory) },
                        onFreeUp: { memory.requestQuit(memory.suggestedIDs) }
                    )
                    levelsSection
                    InsightsSection(
                        forecast: viewModel.diskForecast,
                        advisories: viewModel.advisories,
                        onSelect: { viewModel.focus(on: $0) }
                    )
                }
                .padding(.horizontal, DustyTheme.gutter)
                .padding(.top, 2)
                .padding(.bottom, 20)
                .animation(DustyTheme.revealSpring, value: viewModel.isScanning)
                .animation(DustyTheme.revealSpring, value: viewModel.advisories)
                .animation(DustyTheme.revealSpring, value: viewModel.errorMessage)
            }
            .scrollIndicators(.never)
            footer
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 9) {
            BrandMark(size: 22)
            Text(verbatim: "Dusty")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            if settings.dryRunDefault {
                StatusPill(text: L10n.t("common.dryRun", "Dry Run"), tint: DustyTheme.accent)
                    .help(L10n.t("home.dryRunHelp", "Dry run is on: cleans only report what they would delete."))
            }
            Spacer()
            Button {
                viewModel.open(.settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(DustyIconButtonStyle())
            .keyboardShortcut(",", modifiers: .command)
            .help(L10n.t("common.settings", "Settings"))
            .accessibilityLabel(L10n.t("common.settings", "Settings"))

            Menu {
                Button(L10n.t("menu.deletionLog", "Open Deletion Log")) { viewModel.openDeletionLog() }
                Button(L10n.t("menu.checkUpdates", "Check for Updates…")) { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                Divider()
                Button(L10n.t("menu.quit", "Quit Dusty")) { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 28, height: 28)
            .help(L10n.t("menu.more", "More"))
            .accessibilityLabel(L10n.t("menu.more", "More"))
        }
        .padding(.leading, DustyTheme.gutter)
        .padding(.trailing, 10)
        .frame(height: 50)
    }

    // MARK: - Banners

    @ViewBuilder private var banners: some View {
        if let error = viewModel.errorMessage {
            InlineBanner(
                symbol: "exclamationmark.circle.fill",
                tint: DustyTheme.danger,
                title: error,
                onDismiss: { viewModel.errorMessage = nil }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
        if needsFullDiskAccess && !fdaDismissed {
            InlineBanner(
                symbol: "lock.shield.fill",
                tint: DustyTheme.warn,
                title: L10n.t("fda.title", "Full Disk Access recommended"),
                message: L10n.t("fda.body", "Grant access in System Settings to scan system logs and protected caches."),
                actionTitle: L10n.t("common.open", "Open"),
                action: { viewModel.openFullDiskAccessSettings() },
                onDismiss: { fdaDismissed = true }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var needsFullDiskAccess: Bool {
        CleanupLevel.allCases.contains { viewModel.hasPermissionIssues(for: $0) }
    }

    // MARK: - Levels

    private var levelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: L10n.t("home.levels", "Cleanup levels"),
                detail: viewModel.hasScannedOnce ? Bytes.format(viewModel.totalReclaimableBytes) : nil
            )
            VStack(spacing: 0) {
                ForEach(CleanupLevel.allCases) { level in
                    LevelRow(
                        level: level,
                        result: viewModel.levelResult(for: level),
                        itemCount: viewModel.itemCount(for: level),
                        selectedBytes: viewModel.selectedLevelBytes(level),
                        isScanning: viewModel.isScanning,
                        onOpen: { viewModel.open(.level(level)) }
                    )
                    if level != CleanupLevel.allCases.last {
                        Hairline(leading: 56)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DustyTheme.cardRadius, style: .continuous))
            .dustyCard()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if stats.cleanCount > 0 {
                // The number people screenshot: what Dusty has earned on this Mac.
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(DustyTheme.accent)
                Text(L10n.f("panel.footer.lifetime", "%1$@ reclaimed all-time · %2$d cleans",
                            Bytes.format(stats.lifetimeBytes), stats.cleanCount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(verbatim: "Dusty \(Bundle.main.shortVersion)")
                    .font(.caption)
                    .foregroundStyle(DustyTheme.faint)
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                Text(L10n.t("panel.footer.madeBy", "made by"))
                    .foregroundStyle(DustyTheme.faint)
                Link(destination: URL(string: "https://toprak.sh")!) {
                    Text(verbatim: "toprak.sh")
                }
                .foregroundStyle(.secondary)
                .help(L10n.t("panel.footer.openSite", "Open toprak.sh"))
            }
            .font(.caption)
        }
        .padding(.horizontal, DustyTheme.gutter)
        .frame(height: 36)
        .overlay(alignment: .top) { Hairline() }
    }
}

/// One cleanup level on the home screen: its color, what it holds, and how
/// much it would free. The whole row opens the level.
private struct LevelRow: View {
    let level: CleanupLevel
    let result: LevelScanResult?
    let itemCount: Int
    let selectedBytes: Int64
    let isScanning: Bool
    let onOpen: () -> Void

    private var detail: String {
        guard let result else { return level.blurb }
        if result.totalBytes == 0 || itemCount == 0 {
            return L10n.t("home.level.nothing", "Nothing to clean")
        }
        if selectedBytes == 0 {
            return L10n.f("home.level.noneSelected", "%d items · pick what to remove", itemCount)
        }
        return L10n.f("home.level.selected", "%1$d items · %2$@ selected", itemCount, Bytes.format(selectedBytes))
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                IconTile(symbol: level.symbol, tint: level.tint, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.name)
                        .font(.body.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DustyTheme.faint)
            }
            .padding(.leading, 13)
            .padding(.trailing, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(DustyRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(level.title)
        .accessibilityValue(result.map { Bytes.format($0.totalBytes) } ?? level.blurb)
        .accessibilityHint(L10n.t("home.level.hint", "Shows every item found at this level"))
    }

    @ViewBuilder private var trailing: some View {
        if let result, result.totalBytes > 0 {
            Text(Bytes.format(result.totalBytes))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
        } else if result != nil {
            // Scanned and empty: a quiet tick says "done here" better than "0 MB".
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DustyTheme.success)
                .accessibilityHidden(true)
        } else if isScanning {
            Spinner(size: 12)
        } else {
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DustyTheme.faint)
                .accessibilityHidden(true)
        }
    }
}
