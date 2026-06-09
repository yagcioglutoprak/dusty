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

    private var diskColor: Color { DustyTheme.diskColor(ratio: ratio) }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // Halo: the ring's color bled softly into the surface behind it.
                Circle()
                    .fill(diskColor)
                    .frame(width: 130, height: 130)
                    .blur(radius: 38)
                    .opacity(0.28)

                Circle()
                    .stroke(Color.primary.opacity(0.07), lineWidth: 14)

                Circle()
                    .trim(from: 0, to: max(0.02, ratio))
                    .stroke(
                        DustyTheme.diskGradient(ratio: ratio),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: diskColor.opacity(0.5), radius: 6)
                    .animation(.spring(response: 0.8, dampingFraction: 0.8), value: ratio)

                VStack(spacing: 4) {
                    Image(systemName: ratio < 0.15 ? "externaldrive.badge.exclamationmark" : "internaldrive.fill")
                        .font(.title)
                        .foregroundStyle(diskColor)
                        .symbolRenderingMode(.hierarchical)

                    Text(DiskSpaceMonitor.formatBytes(freeBytes))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: freeBytes)

                    Text("FREE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(2)
                }
            }
            .frame(width: 150, height: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Disk space")
            .accessibilityValue("\(DiskSpaceMonitor.formatBytes(freeBytes)) free of \(DiskSpaceMonitor.formatBytes(totalBytes)), \(usedPercent) percent used")

            HStack(spacing: 10) {
                statPill(label: "USED", value: "\(usedPercent)%")
                statPill(label: "TOTAL", value: DiskSpaceMonitor.formatBytes(totalBytes))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func statPill(label: String, value: String) -> some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Text(value)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(Color.primary.opacity(0.05))
                .overlay(Capsule().stroke(DustyTheme.hairline, lineWidth: 1))
        )
    }
}
