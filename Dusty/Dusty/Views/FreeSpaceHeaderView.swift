import SwiftUI
import CleanerEngine

struct FreeSpaceHeaderView: View {
    let freeBytes: Int64
    let totalBytes: Int64
    let ratio: Double

    private var usedPercent: Int {
        guard totalBytes > 0 else { return 0 }
        return Int((1 - ratio) * 100)
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: max(0.02, ratio))
                    .stroke(
                        DustyTheme.diskGradient(ratio: ratio),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: ratio)

                VStack(spacing: 3) {
                    Image(systemName: ratio < 0.15 ? "externaldrive.badge.exclamationmark" : "internaldrive.fill")
                        .font(.title2)
                        .foregroundStyle(DustyTheme.diskColor(ratio: ratio))
                        .symbolRenderingMode(.hierarchical)

                    Text(DiskSpaceMonitor.formatBytes(freeBytes))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()

                    Text("available")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
            }
            .frame(width: 130, height: 130)

            HStack(spacing: 16) {
                statPill(label: "Used", value: "\(usedPercent)%")
                statPill(label: "Total", value: DiskSpaceMonitor.formatBytes(totalBytes))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
    }
}
