import SwiftUI

enum DustyTheme {
    static let accent = Color.accentColor
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let panelBackground = Color(nsColor: .windowBackgroundColor)

    static func diskColor(ratio: Double) -> Color {
        switch ratio {
        case ..<0.08: return .red
        case ..<0.15: return .orange
        case ..<0.25: return .yellow
        default: return .green
        }
    }

    static func diskGradient(ratio: Double) -> AngularGradient {
        let color = diskColor(ratio: ratio)
        return AngularGradient(
            gradient: Gradient(colors: [color.opacity(0.6), color, color.opacity(0.85)]),
            center: .center
        )
    }

    static let cornerRadius: CGFloat = 12
    static let panelWidth: CGFloat = 440
    static let panelHeight: CGFloat = 620
}
