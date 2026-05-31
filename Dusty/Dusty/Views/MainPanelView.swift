import SwiftUI
import AppKit
import CleanerEngine

struct MainPanelView: View {
    @ObservedObject var viewModel: DustyViewModel
    @ObservedObject var settings: AppSettings
    @State private var showFDABanner = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            scrollContent
            Divider()
            footer
        }
        .frame(width: DustyTheme.panelWidth, height: DustyTheme.panelHeight)
        .background(DustyTheme.panelBackground)
        .task {
            viewModel.scanIfNeeded(settings: settings)
        }
        .onAppear {
            viewModel.startAutoRefresh(interval: settings.refreshIntervalSeconds)
            viewModel.refreshFreeSpace()
        }
        .onChange(of: settings.refreshIntervalSeconds) { newValue in
            viewModel.startAutoRefresh(interval: newValue)
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(settings: settings, onRefreshIntervalChanged: { interval in
                viewModel.startAutoRefresh(interval: interval)
            }, onDone: { viewModel.showSettings = false })
        }
        .sheet(item: $viewModel.pendingConfirmationLevel) { level in
            if viewModel.levelResult(for: level) != nil {
                ConfirmationSheet(
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
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(DustyTheme.diskColor(ratio: viewModel.freeSpaceRatio))
                    Text("Dusty")
                        .font(.headline.weight(.semibold))
                }
                Spacer()
                if viewModel.isDiskLow {
                    Text("LOW DISK")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red.opacity(0.12)))
                }
                Button {
                    viewModel.showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
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
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                scanSection
                    .padding(.horizontal, 14)

                if viewModel.hasScannedOnce && !viewModel.isScanning && viewModel.hasReclaimableSpace {
                    ReclaimSummaryView(
                        totalBytes: viewModel.totalReclaimableBytes,
                        bytesByLevel: CleanupLevel.allCases.map { ($0, viewModel.reclaimableBytes(for: $0)) },
                        safeBytes: viewModel.cleanableBytes(for: .safe),
                        isCleaningSafe: viewModel.isCleaning && viewModel.cleaningLevel == .safe,
                        canCleanSafe: viewModel.canClean(level: .safe),
                        onCleanSafe: { viewModel.cleanSafe() }
                    )
                    .padding(.horizontal, 14)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }

                if showFDABanner && needsFDABanner {
                    FullDiskAccessBanner {
                        viewModel.openFullDiskAccessSettings()
                    }
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let result = viewModel.lastDeletionResult {
                    DeletionResultBanner(result: result, style: viewModel.bannerStyle,
                                         onUndo: { viewModel.undoLastDeletion() })
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let error = viewModel.errorMessage {
                    errorBanner(error)
                        .padding(.horizontal, 14)
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
                    .padding(.horizontal, 14)
                }
            }
            .padding(.vertical, 12)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.isScanning)
            .animation(.easeInOut(duration: 0.25), value: viewModel.lastDeletionResult != nil)
            .animation(.easeInOut(duration: 0.25), value: viewModel.errorMessage)
            .animation(.easeInOut(duration: 0.25), value: viewModel.expandedLevels)
        }
    }

    private var scanSection: some View {
        VStack(spacing: 8) {
            Button {
                viewModel.startScan(settings: settings)
            } label: {
                HStack {
                    if viewModel.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(viewModel.isScanning ? "Scanning…" : viewModel.hasScannedOnce ? "Rescan" : "Scan")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isScanning || viewModel.isCleaning)

            if let progress = viewModel.scanProgress, viewModel.isScanning {
                VStack(spacing: 4) {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                    HStack {
                        Text("\(progress.completed)/\(progress.total) · \(progress.currentTargetName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Cancel") { viewModel.cancelScan() }
                            .buttonStyle(.link)
                            .font(.caption2)
                    }
                }
            } else if let scannedAt = viewModel.scanResult?.scannedAt {
                Text("Last scan: \(scannedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var needsFDABanner: Bool {
        CleanupLevel.allCases.contains { viewModel.hasPermissionIssues(for: $0) }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
    }

    private func toggleLevel(_ level: CleanupLevel) {
        if viewModel.expandedLevels.contains(level) {
            viewModel.expandedLevels.remove(level)
        } else {
            viewModel.expandedLevels.insert(level)
        }
    }

    private var footer: some View {
        VStack(spacing: 7) {
            HStack {
                Button("Deletion log") {
                    viewModel.openDeletionLog()
                }
                .buttonStyle(.link)
                .font(.caption)

                Spacer()

                if settings.dryRunDefault {
                    Label("Dry Run", systemImage: "eye")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
                .font(.caption)
                .keyboardShortcut("q")
            }

            HStack(spacing: 3) {
                Text("made by")
                    .foregroundStyle(.tertiary)
                Link("toprak.sh", destination: URL(string: "https://toprak.sh")!)
                    .foregroundStyle(.secondary)
                    .help("Open toprak.sh")
            }
            .font(.caption2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 11)
    }
}
