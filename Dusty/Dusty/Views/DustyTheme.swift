import SwiftUI
import AppKit

/// Dusty's design system.
///
/// The identity is "dust caught in golden-hour light": a warm amber brand ramp
/// over warm-ink (dark) or warm-paper (light) surfaces. Every color is a wide
/// gamut Display P3 token tuned separately for each appearance, so contrast
/// holds in both modes instead of one mode borrowing the other's values.
/// Semantic colors (success, info, warn, danger) carry meaning; gold carries
/// the brand voice.
enum DustyTheme {

    // MARK: - Dimensions

    static let panelWidth: CGFloat = 468
    static let panelHeight: CGFloat = 676
    static let cornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 12

    // MARK: - Motion

    /// Shared rhythm for micro-interactions, so every control moves the same way.
    static let pressSpring = Animation.spring(response: 0.28, dampingFraction: 0.75)
    static let revealSpring = Animation.spring(response: 0.4, dampingFraction: 0.85)

    // MARK: - Adaptive color

    /// A color that resolves per appearance, with both variants in Display P3.
    private static func adaptive(light: (Double, Double, Double),
                                 dark: (Double, Double, Double),
                                 alpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(displayP3Red: r, green: g, blue: b, alpha: alpha)
        })
    }

    private static func p3(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.displayP3, red: r, green: g, blue: b)
    }

    // MARK: - Brand ramp (dust gold)

    /// The high end of the ramp: dust lit from behind.
    static let goldLight = p3(1.00, 0.85, 0.45)
    /// The signature accent.
    static let gold = p3(0.99, 0.72, 0.24)
    /// Deeper ember, for gradient ends, pressed states, and glows.
    static let goldDeep = p3(0.91, 0.51, 0.13)
    /// Near-black ink that reads as "premium" on top of gold fills.
    static let onGold = p3(0.21, 0.13, 0.03)

    static let accent = gold

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [goldLight, gold, goldDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Surfaces

    /// Panel base: warm paper in light mode, warm ink in dark mode. A custom
    /// surface (not the system window color) so the warmth of the brand carries
    /// through the whole panel instead of sitting on neutral gray.
    static let panelBackground = adaptive(light: (0.962, 0.954, 0.940),
                                          dark: (0.094, 0.088, 0.082))

    /// Raised card surface, one step above the panel.
    static let cardBackground = adaptive(light: (1.0, 0.998, 0.992),
                                         dark: (0.150, 0.142, 0.132))

    /// Hairline borders and dividers, visible in both appearances.
    static let hairline = adaptive(light: (0, 0, 0), dark: (1, 1, 1),
                                   alpha: 0.09)

    /// A whisper of light along a card's top edge; sells the elevation in dark mode.
    static let cardTopLight = adaptive(light: (1, 1, 1), dark: (1, 1, 1),
                                       alpha: 0.10)

    /// Subtle fill for ghost controls.
    static let quietFill = Color.primary.opacity(0.055)
    static let quietFillHover = Color.primary.opacity(0.09)

    // MARK: - Semantic palette

    static let success = adaptive(light: (0.08, 0.58, 0.36), dark: (0.36, 0.84, 0.58))
    static let info = adaptive(light: (0.13, 0.42, 0.90), dark: (0.45, 0.67, 1.00))
    static let warn = adaptive(light: (0.82, 0.38, 0.08), dark: (1.00, 0.58, 0.32))
    static let danger = adaptive(light: (0.79, 0.18, 0.16), dark: (1.00, 0.45, 0.41))

    // MARK: - Disk health (semantic gauge)

    static func diskColor(ratio: Double) -> Color {
        switch ratio {
        case ..<0.08: return danger
        case ..<0.15: return warn
        case ..<0.25: return gold
        default:       return success
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
        case 1: return success
        case 2: return info
        default: return warn
        }
    }

    // MARK: - Depth

    /// Soft ambient elevation for cards.
    static let cardShadow = adaptive(light: (0, 0, 0), dark: (0, 0, 0), alpha: 0.14)
    /// Heavier shadow under in-panel overlays.
    static let overlayShadow = Color.black.opacity(0.32)
}

// MARK: - Card surface

extension View {
    /// Standard Dusty card: filled, gently elevated, with a hairline border that
    /// catches light along the top edge.
    func dustyCard(cornerRadius: CGFloat = DustyTheme.cardCornerRadius,
                   fill: AnyShapeStyle = AnyShapeStyle(DustyTheme.cardBackground)) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .shadow(color: DustyTheme.cardShadow, radius: 9, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [DustyTheme.cardTopLight, DustyTheme.hairline],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Buttons

/// The one gold action on screen: brand gradient, ink text, a glow that leans
/// in on hover, and a soft press. Used for the primary CTA only.
struct DustyPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.body.weight(.bold))
                .foregroundStyle(DustyTheme.onGold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: DustyTheme.controlCornerRadius, style: .continuous)
                        .fill(DustyTheme.brandGradient)
                        .brightness(hovering && isEnabled ? 0.06 : 0)
                        .shadow(color: DustyTheme.goldDeep.opacity(isEnabled ? (hovering ? 0.45 : 0.30) : 0),
                                radius: hovering ? 10 : 7, y: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DustyTheme.controlCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                        .blendMode(.plusLighter)
                )
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(DustyTheme.pressSpring, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// Compact tinted button. `prominent` fills with the tint (white label) for the
/// committed action; otherwise a quiet tinted wash with the tint as the label.
struct DustyTintedButtonStyle: ButtonStyle {
    var tint: Color
    var prominent = false
    /// Label color when prominent; white suits most tints, ink suits gold.
    var prominentLabel: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, tint: tint, prominent: prominent, prominentLabel: prominentLabel)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let tint: Color
        let prominent: Bool
        let prominentLabel: Color
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.subheadline.weight(.bold))
                .foregroundStyle(prominent ? prominentLabel : tint)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(prominent ? tint.opacity(1) : tint.opacity(hovering && isEnabled ? 0.20 : 0.14))
                        .brightness(prominent && hovering && isEnabled ? 0.07 : 0)
                        .shadow(color: prominent && isEnabled ? tint.opacity(0.35) : .clear, radius: 5, y: 2)
                )
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(DustyTheme.pressSpring, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// Quiet full-width utility button (scan, cancel): a soft fill that wakes on hover.
struct DustyGhostButtonStyle: ButtonStyle {
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, fullWidth: fullWidth)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let fullWidth: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.vertical, fullWidth ? 12 : 7)
                .padding(.horizontal, fullWidth ? 0 : 13)
                .background(
                    RoundedRectangle(cornerRadius: DustyTheme.controlCornerRadius, style: .continuous)
                        .fill(hovering && isEnabled ? DustyTheme.quietFillHover : DustyTheme.quietFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DustyTheme.controlCornerRadius, style: .continuous)
                        .strokeBorder(DustyTheme.hairline, lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .opacity(isEnabled ? 1 : 0.5)
                .animation(DustyTheme.pressSpring, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// Bare icon button (header gear, dismiss x) with a hover halo.
struct DustyIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .padding(6)
                .background(Circle().fill(hovering ? DustyTheme.quietFillHover : .clear))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
                .animation(DustyTheme.pressSpring, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}
