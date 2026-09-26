import SwiftUI
import AppKit
import CleanerEngine

/// The whole panel: one screen at a time (home, a cleanup level, settings)
/// with the receipt toast and the confirmation sheet layered on top.
///
/// Everything is drawn inside the panel, never as a system sheet or popover. A
/// `MenuBarExtra(.window)` panel is a non-activating `NSPanel` that closes the
/// instant a modal sheet pulls focus away, which would dismiss the whole UI
/// mid-action. Keeping every interaction in-panel avoids the focus loss entirely.
struct MainPanelView: View {
    @ObservedObject var viewModel: DustyViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: Updater
    @ObservedObject var memory: MemoryModel

    /// The level awaiting confirmation, once its scan result exists.
    private var sheetLevel: CleanupLevel? {
        guard let level = viewModel.pendingConfirmationLevel,
              viewModel.levelResult(for: level) != nil else { return nil }
        return level
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PanelBackdrop()

            screen
                .disabled(sheetLevel != nil || memory.pendingQuit != nil || memory.pendingRelaunch != nil)

            if settings.hasSeenWelcome, sheetLevel == nil, let result = viewModel.lastDeletionResult {
                ResultToast(
                    result: result,
                    style: viewModel.bannerStyle,
                    undoDeadline: viewModel.undoDeadline,
                    undoWindow: DustyViewModel.undoWindow,
                    onUndo: { viewModel.undoLastDeletion() },
                    onDismiss: { viewModel.dismissResult() }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, toastBottomInset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            } else if settings.hasSeenWelcome, sheetLevel == nil, memory.pendingQuit == nil, memory.pendingRelaunch == nil,
                      let receipt = memory.receipt {
                MemoryToast(
                    receipt: receipt,
                    reopenDeadline: memory.reopenDeadline,
                    reopenWindow: MemoryModel.reopenWindow,
                    onReopen: { memory.reopenQuitApps() },
                    onDismiss: { memory.dismissReceipt() }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, toastBottomInset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }

            if let pending = memory.pendingQuit, sheetLevel == nil {
                Color.black.opacity(0.34)
                    .contentShape(Rectangle())
                    .onTapGesture { memory.cancelQuit() }
                    .transition(.opacity)
                    .zIndex(2)
                MemoryQuitSheet(
                    apps: pending,
                    availableBefore: memory.snapshot?.availableBytes ?? 0,
                    availableAfter: memory.projectedAvailable(afterFreeing: pending.reduce(0) { $0 + $1.footprintBytes }),
                    onConfirm: { Task { await memory.confirmQuit() } },
                    onCancel: { memory.cancelQuit() }
                )
                .transition(.move(edge: .bottom))
                .zIndex(3)
            }

            if let app = memory.pendingRelaunch, sheetLevel == nil, memory.pendingQuit == nil {
                Color.black.opacity(0.34)
                    .contentShape(Rectangle())
                    .onTapGesture { memory.cancelRelaunch() }
                    .transition(.opacity)
                    .zIndex(2)
                MemoryQuitSheet(
                    apps: [app],
                    availableBefore: 0,
                    availableAfter: 0,
                    relaunch: true,
                    growth: memory.growth[app.id],
                    onConfirm: { Task { await memory.confirmRelaunch() } },
                    onCancel: { memory.cancelRelaunch() }
                )
                .transition(.move(edge: .bottom))
                .zIndex(3)
            }

            if let level = sheetLevel {
                Color.black.opacity(0.34)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.cancelConfirmation() }
                    .transition(.opacity)
                    .zIndex(2)
                confirmation(for: level)
                    .transition(.move(edge: .bottom))
                    .zIndex(3)
            }
        }
        .frame(width: DustyTheme.panelWidth, height: DustyTheme.panelHeight)
        .clipped()
        .background(quitShortcut)
        .animation(DustyTheme.navSpring, value: viewModel.route)
        .animation(DustyTheme.navSpring, value: settings.hasSeenWelcome)
        .animation(DustyTheme.revealSpring, value: sheetLevel)
        .animation(DustyTheme.revealSpring, value: viewModel.lastDeletionResult != nil)
        .animation(DustyTheme.revealSpring, value: memory.pendingQuit != nil)
        .animation(DustyTheme.revealSpring, value: memory.pendingRelaunch != nil)
        .animation(DustyTheme.revealSpring, value: memory.receipt != nil)
        .task {
            // First launch holds the silent auto-scan: the welcome screen explains
            // the model first and its button starts the scan, so the first scan is chosen.
            if settings.hasSeenWelcome {
                viewModel.scanIfNeeded(settings: settings)
            }
        }
        .onAppear {
            viewModel.startAutoRefresh(interval: settings.refreshIntervalSeconds)
            memory.panelOpened()
        }
        .onChange(of: settings.refreshIntervalSeconds) { newValue in
            viewModel.startAutoRefresh(interval: newValue)
        }
    }

    // MARK: - Screens

    @ViewBuilder private var screen: some View {
        if !settings.hasSeenWelcome {
            WelcomeView(
                onScan: {
                    settings.hasSeenWelcome = true
                    viewModel.startScan(settings: settings)
                },
                onSkip: { settings.hasSeenWelcome = true }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
            switch viewModel.route {
            case .home:
                HomeView(viewModel: viewModel, settings: settings, updater: updater, memory: memory)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .level(let level):
                LevelDetailView(level: level, viewModel: viewModel, settings: settings)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .memory:
                MemoryView(memory: memory, viewModel: viewModel, settings: settings)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .settings:
                SettingsView(settings: settings, updater: updater, viewModel: viewModel)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private func confirmation(for level: CleanupLevel) -> some View {
        let paths = viewModel.cleanablePaths(for: level)
        let bytes = paths.reduce(Int64(0)) { $0 + $1.estimatedBytes }
        let groups = (viewModel.levelResult(for: level)?.targetResults ?? []).compactMap { target -> ConfirmationGroup? in
            let picked = paths.filter { $0.targetID == target.id }
            guard !picked.isEmpty else { return nil }
            return ConfirmationGroup(
                id: target.id,
                name: target.target.localizedName,
                paths: picked.sorted { $0.estimatedBytes > $1.estimatedBytes }
            )
        }
        .sorted { $0.bytes > $1.bytes }
        let keepsInTrash = settings.moveToTrashDefault && level != .safe

        return ConfirmationSheet(
            level: level,
            groups: groups,
            bytes: bytes,
            itemCount: paths.count,
            dryRun: settings.dryRunDefault,
            moveToTrash: keepsInTrash,
            skippedApps: viewModel.blockingApps(for: level),
            freeBefore: viewModel.freeSpaceBytes,
            freeAfter: keepsInTrash ? nil : viewModel.projectedFreeBytes(afterReclaiming: bytes),
            onConfirm: {
                Task { await viewModel.confirmClean(level: level, settings: settings) }
            },
            onCancel: { viewModel.cancelConfirmation() }
        )
    }

    /// On a level screen the receipt floats above the sticky Clean bar instead
    /// of over it, so the next clean is never blocked by the last one's receipt.
    private var toastBottomInset: CGFloat {
        if case .level(let level) = viewModel.route, viewModel.levelResult(for: level) != nil {
            return 66
        }
        if viewModel.route == .memory {
            return 66
        }
        return 12
    }

    /// ⌘Q from any screen, the way every menu bar app behaves.
    private var quitShortcut: some View {
        Button("") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The panel surface: the neutral canvas with a faint wash of the brand
/// gradient pooled in the top corners.
private struct PanelBackdrop: View {
    var body: some View {
        ZStack {
            DustyTheme.canvas
            RadialGradient(
                colors: [DustyTheme.sky.opacity(0.10), .clear],
                center: UnitPoint(x: 0.1, y: 0),
                startRadius: 0,
                endRadius: 300
            )
            RadialGradient(
                colors: [DustyTheme.indigo.opacity(0.09), .clear],
                center: UnitPoint(x: 0.95, y: 0.02),
                startRadius: 0,
                endRadius: 260
            )
        }
        .ignoresSafeArea()
    }
}
