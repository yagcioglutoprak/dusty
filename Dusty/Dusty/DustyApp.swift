import SwiftUI
import CleanerEngine

@main
struct DustyApp: App {
    @StateObject private var viewModel = DustyViewModel()
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra {
            MainPanelView(viewModel: viewModel, settings: settings)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.isDiskLow ? "externaldrive.badge.exclamationmark" : "internaldrive.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(viewModel.isDiskLow ? .red : .primary)
                Text(viewModel.menuBarLabel)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings) { interval in
                viewModel.startAutoRefresh(interval: interval)
            }
        }
    }
}
