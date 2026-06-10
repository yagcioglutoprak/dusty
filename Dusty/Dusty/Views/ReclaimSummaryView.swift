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
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(DustyTheme.gold)
                    Text("RECLAIMABLE")
                        .font(.caption.weight(.bold))
                        .tracking(1.8)
                        .foregroundStyle(.secondary)
                }
                Text(DiskSpaceMonitor.formatBytes(totalBytes))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: totalBytes)
                    .foregroundStyle(.primary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Reclaimable space")
            .accessibilityValue(DiskSpaceMonitor.formatBytes(totalBytes))

            HStack(spacing: 8) {
                ForEach(bytesByLevel.filter { $0.bytes > 0 }, id: \.level) { item in
                    HStack(spacing: 6) {
                        Circle().fill(color(for: item.level)).frame(width: 8, height: 8)
                        Text(DiskSpaceMonitor.formatBytes(item.bytes))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(color(for: item.level).opacity(0.12)))
                }
            }

            Button(action: onCleanSafe) {
                HStack(spacing: 8) {
                    if isCleaningSafe {
                        ProgressView()
                            .controlSize(.small)
                            .tint(DustyTheme.onGold)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.body.weight(.bold))
                    }
                    Text(safeBytes > 0
                         ? "Clean Safe · \(DiskSpaceMonitor.formatBytes(safeBytes))"
                         : "Nothing safe to clean")
                        .monospacedDigit()
                }
            }
            .buttonStyle(DustyPrimaryButtonStyle())
            .disabled(safeBytes == 0 || isCleaningSafe || !canCleanSafe)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .background(
            // The brand moment: a faint pool of gold light behind the headline,
            // so the hero card reads warmer than the cards below it.
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DustyTheme.gold.opacity(0.10), DustyTheme.gold.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: DustyTheme.cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [DustyTheme.gold.opacity(0.30), DustyTheme.hairline],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: DustyTheme.cardShadow, radius: 12, y: 5)
    }

    private func color(for level: CleanupLevel) -> Color {
        DustyTheme.levelColor(level.rawValue)
    }
}
