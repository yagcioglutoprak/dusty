import SwiftUI
import CleanerEngine

@main
struct DustyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // A snapshot run builds inert models: no timers, no background scans, no
    // Sparkle, so the rendered panel shows fixtures and nothing else.
    @StateObject private var viewModel = DustyViewModel(startsServices: !SnapshotMode.isActive)
    @StateObject private var settings = AppSettings.shared
    @StateObject private var updater = Updater(startingUpdater: !SnapshotMode.isActive)
    @StateObject private var memory = MemoryModel(startsServices: !SnapshotMode.isActive)

    var body: some Scene {
        MenuBarExtra {
            MainPanelView(viewModel: viewModel, settings: settings, updater: updater, memory: memory)
        } label: {
            // Kept inline (not a child view) so the label re-renders whenever the
            // app-level objects publish; a menu bar label is a fragile place for a
            // separate observer.
            HStack(spacing: 4) {
                Image(systemName: viewModel.isDiskLow ? "externaldrive.badge.exclamationmark" : "internaldrive.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(viewModel.isDiskLow ? .red : .primary)
                if let text = menuBarText {
                    Text(text)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// Free space (bytes or percent, per settings) plus a quiet "to clean" suffix
    /// once a background scan has found a meaningful amount, and memory in use
    /// when that is switched on. Nil in icon-only mode.
    private var menuBarText: String? {
        let label: String
        switch settings.menuBarStyle {
        case .iconOnly: return nil
        case .percentage: label = viewModel.menuBarPercentLabel
        case .freeSpace: label = viewModel.menuBarLabel
        }
        var text = label
        if settings.menuBarShowsReclaimable, let reclaimable = viewModel.menuBarReclaimableSuffix {
            text = L10n.f("menubar.toClean", "%1$@ · %2$@ to clean", label, reclaimable)
        }
        if settings.menuBarShowsMemory, let percent = memory.usedPercent {
            text += " · " + L10n.f("menubar.memory", "RAM %d%%", percent)
        }
        return text
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let directory = SnapshotMode.outputDirectory {
            Task { @MainActor in
                await SnapshotRenderer.renderAll(to: directory)
                exit(0)
            }
        }
        #endif
    }
}

/// `--render-snapshots <dir>` (Debug builds only) renders every panel state to
/// PNGs and quits. CI uses it to show what a change looks like.
enum SnapshotMode {
    static let flag = "--render-snapshots"

    static var isActive: Bool {
        #if DEBUG
        return outputDirectory != nil
        #else
        return false
        #endif
    }

    static var outputDirectory: URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }
}
