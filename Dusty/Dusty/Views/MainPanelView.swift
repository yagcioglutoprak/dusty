import SwiftUI
import AppKit
import CleanerEngine

struct MainPanelView: View {
    @ObservedObject var viewModel: DustyViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: Updater
    @ObservedObject private var stats = CleanStatsStore.shared
    @State private var showFDABanner = true
    @State private var appeared = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.5)
                scrollContent
                Divider().opacity(0.5)
                footer
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)

            overlay
        }
        .frame(width: DustyTheme.panelWidth, height: DustyTheme.panelHeight)
        .background(panelBackground)
        .animation(.easeInOut(duration: 0.18), value: viewModel.showSettings)
        .animation(.easeInOut(duration: 0.18), value: viewModel.pendingConfirmationLevel)
        .animation(.easeInOut(duration: 0.18), value: settings.hasSeenWelcome)
        .task {
            // First launch holds the silent auto-scan: the welcome card explains the
            // model first and its button starts the scan, so the first scan is chosen.
            if settings.hasSeenWelcome {
                viewModel.scanIfNeeded(settings: settings)
            }
        }
        .onAppear {
            viewModel.startAutoRefresh(interval: settings.refreshIntervalSeconds)
            viewModel.refreshFreeSpace()
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
        }
        .onChange(of: settings.refreshIntervalSeconds) { newValue in
            viewModel.startAutoRefresh(interval: newValue)
        }
    }

    /// Atmosphere, not a flat fill: a warm dust-gold glow pools behind the disk
    /// ring up top, with a faint shadow gathering at the base for depth. Reads
    /// well in both light and dark appearances.
    private var panelBackground: some View {
        ZStack {
            DustyTheme.panelBackground
            RadialGradient(
                colors: [DustyTheme.gold.opacity(0.07), .clear],
                center: UnitPoint(x: 0.5, y: 0.12),
                startRadius: 4,
                endRadius: 290
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.05)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    /// Confirmation and settings are drawn inside the panel, never as sheets. A
    /// `MenuBarExtra(.window)` panel is a non-activating `NSPanel` that closes the
    /// instant a modal sheet pulls focus away, which would dismiss the whole UI
    /// mid-action: the cause of "clicking Delete does nothing" and "buttons close
    /// the app". Keeping every interaction in-panel avoids the focus loss entirely.
    @ViewBuilder private var overlay: some View {
        if !settings.hasSeenWelcome {
            OverlayScrim {}
            WelcomeCard(
                onScan: {
                    settings.hasSeenWelcome = true
                    viewModel.startScan(settings: settings)
                },
                onSkip: { settings.hasSeenWelcome = true }
            )
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else if viewModel.showSettings {
            OverlayScrim { viewModel.showSettings = false }
            SettingsView(settings: settings, updater: updater, onRefreshIntervalChanged: { interval in
                viewModel.startAutoRefresh(interval: interval)
            }, onDone: { viewModel.showSettings = false })
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else if let level = viewModel.pendingConfirmationLevel,
                  viewModel.levelResult(for: level) != nil {
            OverlayScrim { viewModel.cancelConfirmation() }
            ConfirmationCard(
                level: level,
                paths: viewModel.cleanablePaths(for: level),
                bytes: viewModel.cleanableBytes(for: level),
                dryRun: settings.dryRunDefault,
                moveToTrash: settings.moveToTrashDefault && level != .safe,
                skippedApps: viewModel.blockingApps(for: level),
                onConfirm: {
                    Task { await viewModel.confirmClean(level: level, settings: settings) }
                },
                onCancel: { viewModel.cancelConfirmation() }
            )
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(DustyTheme.brandGradient)
                        .frame(width: 26, height: 26)
                        .shadow(color: DustyTheme.goldDeep.opacity(0.35), radius: 4, y: 1)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DustyTheme.onGold)
                }
                .accessibilityHidden(true)
                Text("Dusty")
                    .font(.title3.weight(.bold))
                Spacer()
                if viewModel.isDiskLow {
                    Text("LOW DISK")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DustyTheme.danger)
                        .tracking(0.5)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DustyTheme.danger.opacity(0.14)))
                }
                Button {
                    viewModel.showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(DustyIconButtonStyle())
                .help("Settings")
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            FreeSpaceHeaderView(
                freeBytes: viewModel.freeSpaceBytes,
                totalBytes: viewModel.totalSpaceBytes,
                ratio: viewModel.freeSpaceRatio
            )
            .padding(.bottom, 4)
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                scanSection
                    .padding(.horizontal, 16)

                if viewModel.hasScannedOnce && !viewModel.isScanning {
                    if viewModel.hasReclaimableSpace {
                        ReclaimSummaryView(
                            totalBytes: viewModel.totalReclaimableBytes,
                            bytesByLevel: CleanupLevel.allCases.map { ($0, viewModel.reclaimableBytes(for: $0)) },
                            safeBytes: viewModel.cleanableBytes(for: .safe),
                            isCleaningSafe: viewModel.isCleaning && viewModel.cleaningLevel == .safe,
                            canCleanSafe: viewModel.canClean(level: .safe),
                            onCleanSafe: { viewModel.cleanSafe() }
                        )
                        .padding(.horizontal, 16)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                    } else {
                        AllCleanCard(lastScanAt: viewModel.scanResult?.scannedAt)
                            .padding(.horizontal, 16)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }

                if showFDABanner && needsFDABanner {
                    FullDiskAccessBanner {
                        viewModel.openFullDiskAccessSettings()
                    }
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let result = viewModel.lastDeletionResult {
                    DeletionResultBanner(result: result, style: viewModel.bannerStyle,
                                         onUndo: { viewModel.undoLastDeletion() })
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let error = viewModel.errorMessage {
                    errorBanner(error)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ForEach(CleanupLevel.allCases, id: \.self) { level in
                    LevelSectionView(
                        level: level,
                        levelResult: viewModel.levelResult(for: level),
                        selectedBytes: viewModel.selectedLevelBytes(level),
                        isExpanded: viewModel.expandedLevels.contains(level),
                        isCleaning: viewModel.isCleaning && viewModel.cleaningLevel == level,
                        canClean: viewModel.canClean(level: level),
                        blockingApps: viewModel.blockingApps(for: level),
                        onToggleExpand: { toggleLevel(level) },
                        onClean: { viewModel.requestClean(level: level) },
                        onTogglePath: { targetID, pathID in
                            viewModel.togglePathSelection(level: level, targetID: targetID, pathID: pathID)
                        },
                        onSelectAll: { targetID, selected in
                            viewModel.setAllSelected(level: level, targetID: targetID, selected: selected)
                        }
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.isScanning)
            .animation(.easeInOut(duration: 0.25), value: viewModel.lastDeletionResult != nil)
            .animation(.easeInOut(duration: 0.25), value: viewModel.errorMessage)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.expandedLevels)
        }
    }

    private var scanSection: some View {
        VStack(spacing: 10) {
            Button {
                viewModel.startScan(settings: settings)
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DustyTheme.gold)
                    }
                    Text(viewModel.isScanning ? "Scanning…" : viewModel.hasScannedOnce ? "Rescan" : "Scan disk")
                }
            }
            .buttonStyle(DustyGhostButtonStyle())
            .disabled(viewModel.isScanning || viewModel.isCleaning)

            if let progress = viewModel.scanProgress, viewModel.isScanning {
                VStack(spacing: 6) {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .tint(DustyTheme.gold)
                    HStack {
                        Text("\(progress.completed)/\(progress.total) · \(progress.currentTargetName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Cancel") { viewModel.cancelScan() }
                            .buttonStyle(.link)
                            .font(.caption.weight(.medium))
                    }
                }
            } else if let scannedAt = viewModel.scanResult?.scannedAt {
                // Relative on purpose: a bare clock time reads as today even when the
                // scan is days old, and this panel can sit unopened for weeks.
                Text("Last scan: \(RelativeTime.label(for: scannedAt))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var needsFDABanner: Bool {
        CleanupLevel.allCases.contains { viewModel.hasPermissionIssues(for: $0) }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.body)
                .foregroundStyle(DustyTheme.danger)
            Text(message)
                .font(.subheadline)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(DustyIconButtonStyle())
            .accessibilityLabel("Dismiss error")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(DustyTheme.danger.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(DustyTheme.danger.opacity(0.22), lineWidth: 1))
    }

    private func toggleLevel(_ level: CleanupLevel) {
        if viewModel.expandedLevels.contains(level) {
            viewModel.expandedLevels.remove(level)
        } else {
            viewModel.expandedLevels.insert(level)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if stats.cleanCount > 0 {
                // The number people screenshot: what Dusty has earned on this Mac.
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(DustyTheme.gold)
                    Text("\(DiskSpaceMonitor.formatBytes(stats.lifetimeBytes)) reclaimed all-time · \(stats.cleanCount) clean\(stats.cleanCount == 1 ? "" : "s")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            HStack {
                Button("Deletion log") {
                    viewModel.openDeletionLog()
                }
                .buttonStyle(.link)
                .font(.footnote.weight(.medium))

                Spacer()

                if settings.dryRunDefault {
                    Label("Dry Run", systemImage: "eye")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
                .font(.footnote.weight(.medium))
                .keyboardShortcut("q")
            }

            HStack(spacing: 4) {
                Text("made by")
                    .foregroundStyle(.tertiary)
                Link("toprak.sh", destination: URL(string: "https://toprak.sh")!)
                    .foregroundStyle(.secondary)
                    .help("Open toprak.sh")
            }
            .font(.caption)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 13)
    }
}

/// Empty state for a scan that found nothing: the good news deserves a moment,
/// not a blank list. Quietly notes that the background scanner stays on watch.
private struct AllCleanCard: View {
    let lastScanAt: Date?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(DustyTheme.success.opacity(0.14))
                    .frame(width: 44, height: 44)
                Circle()
                    .strokeBorder(DustyTheme.success.opacity(0.25), lineWidth: 1)
                    .frame(width: 44, height: 44)
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(DustyTheme.success)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("All clean")
                    .font(.body.weight(.semibold))
                Text(lastScanAt.map { "Nothing reclaimable (checked \(RelativeTime.label(for: $0))). Dusty keeps watching in the background." }
                     ?? "Nothing reclaimable right now. Dusty keeps watching in the background.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .dustyCard()
        .accessibilityElement(children: .combine)
    }
}

/// Dimmed, tap-to-dismiss backdrop behind an in-panel overlay. Sized by its
/// container so it covers the full panel and intercepts taps on the content below.
private struct OverlayScrim: View {
    let onTap: () -> Void

    var body: some View {
        Color.black.opacity(0.38)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .transition(.opacity)
    }
}
