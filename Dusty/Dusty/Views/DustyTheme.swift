import SwiftUI

/// Dusty's design system: a warm "dust-gold" signature against an adaptive
/// graphite / warm-white surface. Gold is the brand voice (primary action,
/// sparkle, highlights); the disk-health ring keeps its semantic gauge colors.
enum DustyTheme {

    // MARK: - Dimensions

    static let panelWidth: CGFloat = 468
    static let panelHeight: CGFloat = 676
    static let cornerRadius: CGFloat = 15
    static let cardCornerRadius: CGFloat = 13

    // MARK: - Brand palette (wide gamut)

    /// Dust caught in golden-hour light: the signature accent.
    static let gold = Color(.displayP3, red: 0.97, green: 0.73, blue: 0.27)
    /// Deeper ember, for the lower end of the brand gradient and pressed states.
    static let goldDeep = Color(.displayP3, red: 0.93, green: 0.53, blue: 0.16)
    /// Near-black ink that reads as "premium" on top of gold fills.
    static let onGold = Color(.displayP3, red: 0.16, green: 0.10, blue: 0.02)

    static let accent = gold

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [gold, goldDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Surfaces

    static let panelBackground = Color(nsColor: .windowBackgroundColor)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let hairline = Color.primary.opacity(0.08)

    // MARK: - Disk health (semantic gauge)

    static func diskColor(ratio: Double) -> Color {
        switch ratio {
        case ..<0.08: return Color(.displayP3, red: 0.95, green: 0.27, blue: 0.30)
        case ..<0.15: return Color(.displayP3, red: 0.98, green: 0.55, blue: 0.20)
        case ..<0.25: return Color(.displayP3, red: 0.98, green: 0.78, blue: 0.24)
        default:       return Color(.displayP3, red: 0.30, green: 0.80, blue: 0.50)
        }
    }

    static func diskGradient(ratio: Double) -> AngularGradient {
        let color = diskColor(ratio: ratio)
        return AngularGradient(
            gradient: Gradient(colors: [color.opacity(0.55), color, color.opacity(0.9), color.opacity(0.55)]),
            center: .center
        )
    }

    static func levelColor(_ level: Int) -> Color {
        switch level {
        case 1: return Color(.displayP3, red: 0.30, green: 0.80, blue: 0.50)   // safe
        case 2: return Color(.displayP3, red: 0.36, green: 0.62, blue: 0.98)   // developer
        default: return Color(.displayP3, red: 0.98, green: 0.58, blue: 0.24)  // deep
        }
    }

    // MARK: - Depth

    /// Soft elevation used by hero cards and overlays.
    static let cardShadow = Color.black.opacity(0.16)
    static let overlayShadow = Color.black.opacity(0.30)
}

extension View {
    /// Standard Dusty card surface: filled, hairline-bordered, gently elevated.
    func dustyCard(cornerRadius: CGFloat = DustyTheme.cardCornerRadius,
                   fill: AnyShapeStyle = AnyShapeStyle(DustyTheme.cardBackground)) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .shadow(color: DustyTheme.cardShadow, radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(DustyTheme.hairline, lineWidth: 1)
        )
    }
}
