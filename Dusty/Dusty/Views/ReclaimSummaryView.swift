import SwiftUI
import CleanerEngine

/// Hero card: the "you can reclaim X" moment with a one-tap primary action.
struct ReclaimSummaryView: View {
    let totalBytes: Int64
    let bytesByLevel: [(level: CleanupLevel, bytes: Int64)]
    let safeBytes: Int64
    let isCleaningSafe: Bool
    let canCleanSafe: Bool
    let onCleanSafe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("RECLAIMABLE")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(DiskSpaceMonitor.formatBytes(totalBytes))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            HStack(spacing: 8) {
                ForEach(bytesByLevel.filter { $0.bytes > 0 }, id: \.level) { item in
                    HStack(spacing: 5) {
                        Circle().fill(color(for: item.level)).frame(width: 7, height: 7)
                        Text(DiskSpaceMonitor.formatBytes(item.bytes))
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(color(for: item.level).opacity(0.1)))
                }
            }

            Button(action: onCleanSafe) {
                HStack(spacing: 6) {
                    if isCleaningSafe {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(safeBytes > 0
                         ? "Clean Safe · \(DiskSpaceMonitor.formatBytes(safeBytes))"
                         : "Nothing safe to clean")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(safeBytes == 0 || isCleaningSafe || !canCleanSafe)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DustyTheme.cornerRadius)
                        .stroke(DustyTheme.accent.opacity(0.15))
                )
        )
    }

    private func color(for level: CleanupLevel) -> Color {
        switch level {
        case .safe: return .green
        case .developer: return .blue
        case .deep: return .orange
        }
    }
}
