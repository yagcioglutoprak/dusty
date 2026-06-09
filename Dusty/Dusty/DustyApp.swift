import SwiftUI
import CleanerEngine

@main
struct DustyApp: App {
    @StateObject private var viewModel = DustyViewModel()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var updater = Updater()

    var body: some Scene {
        MenuBarExtra {
            MainPanelView(viewModel: viewModel, settings: settings, updater: updater)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.isDiskLow ? "externaldrive.badge.exclamationmark" : "internaldrive.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(viewModel.isDiskLow ? .red : .primary)
                Text(menuBarText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }

    /// Free space (bytes or percentage, per settings), plus a quiet "to clean" suffix
    /// once a background scan has found a meaningful amount.
    private var menuBarText: String {
        let label = settings.menuBarShowsPercentage ? viewModel.menuBarPercentLabel : viewModel.menuBarLabel
        if let reclaimable = viewModel.menuBarReclaimableSuffix {
            return "\(label) · \(reclaimable) to clean"
        }
        return label
    }
}
