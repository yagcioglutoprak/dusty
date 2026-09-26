import SwiftUI
import AppKit
import CleanerEngine

/// Dusty's design system.
///
/// The identity comes from the app icon: a sky-to-indigo gradient with a
/// sparkle, set on calm neutral surfaces. Color carries meaning, not
/// decoration: the brand gradient marks the one primary action on screen, the
/// three cleanup levels each own a hue (mint, violet, amber) that follows them
/// from the storage bar to the level screen to the confirm button, and the
/// semantic colors (success, warn, danger) only ever report state.
///
/// Every token is tuned separately for light and dark, so contrast holds in both
/// appearances instead of one borrowing the other's values.
enum DustyTheme {

    // MARK: - Layout

    static let panelWidth: CGFloat = 420
    static let panelHeight: CGFloat = 640
    /// Horizontal page margin shared by every screen.
    static let gutter: CGFloat = 16
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 10
    static let sheetRadius: CGFloat = 20

    // MARK: - Motion

    /// Shared rhythm for micro-interactions, so every control moves the same way.
    static let pressSpring = Animation.spring(response: 0.26, dampingFraction: 0.72)
    static let revealSpring = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// Screen pushes and pops inside the panel.
    static let navSpring = Animation.spring(response: 0.42, dampingFraction: 0.9)

    // MARK: - Adaptive color

    /// A color that resolves per appearance, from 0xRRGGBB values in sRGB.
    static func adaptive(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    static func hex(_ value: UInt32, alpha: Double = 1) -> Color {
        Color(nsColor: NSColor(hex: value, alpha: alpha))
    }

    // MARK: - Brand

    /// The icon's gradient, stop for stop: sky, azure, indigo.
    static let sky = hex(0x38C5F5)
    static let azure = hex(0x3B82F6)
    static let indigo = hex(0x6366F1)

    /// Interactive accent for links, focus rings, and selected states.
    static let accent = adaptive(light: 0x2563EB, dark: 0x6AA6FF)

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [sky, azure, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Surfaces

    /// Panel base. Opaque on purpose: a menu bar panel sits over anything, and a
    /// custom surface keeps the palette the same over a white web page or a dark
    /// terminal.
    static let canvas = adaptive(light: 0xF3F4F7, dark: 0x111215)
    /// Raised card, one step above the canvas.
    static let card = adaptive(light: 0xFFFFFF, dark: 0x1B1C21)
    /// Sheets and popovers, one step above cards.
    static let elevated = adaptive(light: 0xFFFFFF, dark: 0x23242A)
    /// Wells, tracks, and the resting fill of quiet controls.
    static let inset = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.05, darkAlpha: 0.07)
    static let insetHover = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.11)
    /// Hairline borders and dividers.
    static let hairline = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.08)
    /// Tertiary text that still passes contrast on cards.
    static let faint = adaptive(light: 0x6B7280, dark: 0x8B8F99)
    /// Soft card shadow: present in light mode, gone in dark where elevation is
    /// carried by the lighter surface instead.
    static let shadow = adaptive(light: 0x0F172A, dark: 0x000000, lightAlpha: 0.07, darkAlpha: 0)

    // MARK: - Semantic

    static let success = adaptive(light: 0x0E9F6E, dark: 0x34D399)
    static let warn = adaptive(light: 0xD97706, dark: 0xFBBF24)
    static let danger = adaptive(light: 0xDC2626, dark: 0xF87171)

    // MARK: - Cleanup levels

    static let safe = adaptive(light: 0x10A37F, dark: 0x3DD6A3)
    static let developer = adaptive(light: 0x7C4DFF, dark: 0xA78BFA)
    static let deep = adaptive(light: 0xEA6A0C, dark: 0xFB9A4B)

    /// The segment of the storage bar that is used but not reclaimable.
    static let usedSpace = adaptive(light: 0x9CA3AF, dark: 0x4B5060)

    // MARK: - Memory

    /// Memory owns a hue of its own, a cyan none of the cleanup levels use, so
    /// the memory card never reads as a fourth level.
    static let memory = adaptive(light: 0x0891B2, dark: 0x22D3EE)
    /// A deeper cut for filled buttons, dark enough under a white label.
    static let memorySolid = hex(0x0E7490)
    /// Compressed memory in the memory bar.
    static let memoryCompressed = adaptive(light: 0x2563EB, dark: 0x60A5FA)

    // MARK: - Disk health

    enum DiskHealth {
        case healthy, gettingFull, low

        init(freeRatio: Double) {
            switch freeRatio {
            case ..<0.15: self = .low
            case ..<0.25: self = .gettingFull
            default: self = .healthy
            }
        }

        var tint: Color {
            switch self {
            case .healthy: return DustyTheme.success
            case .gettingFull: return DustyTheme.warn
            case .low: return DustyTheme.danger
            }
        }

        var label: String {
            switch self {
            case .healthy: return L10n.t("health.healthy", "Healthy")
            case .gettingFull: return L10n.t("health.gettingFull", "Getting full")
            case .low: return L10n.t("health.low", "Low on space")
            }
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}

// MARK: - Level identity

extension CleanupLevel {
    /// Short name for navigation and buttons. The engine's `title` ("Level 1:
    /// Safe") stays the long form for places that need the number.
    var name: String {
        switch self {
        case .safe: return L10n.t("level.name.safe", "Safe")
        case .developer: return L10n.t("level.name.developer", "Developer")
        case .deep: return L10n.t("level.name.deep", "Deep")
        }
    }

    /// One line on what the level holds, sized for a list row.
    var blurb: String {
        switch self {
        case .safe: return L10n.t("level.blurb.safe", "Caches, logs, and Trash. Regenerates on its own.")
        case .developer: return L10n.t("level.blurb.developer", "Build data, simulators, package caches.")
        case .deep: return L10n.t("level.blurb.deep", "Installers, archives, snapshots. Pick by hand.")
        }
    }

    var symbol: String {
        switch self {
        case .safe: return "leaf.fill"
        case .developer: return "hammer.fill"
        case .deep: return "archivebox.fill"
        }
    }

    var tint: Color {
        switch self {
        case .safe: return DustyTheme.safe
        case .developer: return DustyTheme.developer
        case .deep: return DustyTheme.deep
        }
    }

    /// A deeper cut of the tint for filled buttons, dark enough under a white
    /// label in both appearances (the dark-mode tints are too light for that).
    var solid: Color {
        switch self {
        case .safe: return DustyTheme.hex(0x0B8A6A)
        case .developer: return DustyTheme.hex(0x6B3EF0)
        case .deep: return DustyTheme.hex(0xC9530A)
        }
    }
}

// MARK: - Surfaces

extension View {
    /// Standard Dusty card: filled, hairline-bordered, softly lifted in light mode.
    func dustyCard(radius: CGFloat = DustyTheme.cardRadius, fill: Color = DustyTheme.card) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .shadow(color: DustyTheme.shadow, radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(DustyTheme.hairline, lineWidth: 1)
        )
    }

    /// A tinted callout surface (warnings, errors, receipts).
    func dustyCallout(tint: Color, radius: CGFloat = 12) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(tint.opacity(0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(tint.opacity(0.24), lineWidth: 1)
        )
    }
}

// MARK: - Buttons

/// The one gradient action on screen: brand gradient, white label, a lift on
/// hover, and a soft press. `tint` swaps the gradient for a level color when
/// the action belongs to one level.
struct DustyPrimaryButtonStyle: ButtonStyle {
    var tint: Color? = nil
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, tint: tint, compact: compact)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let tint: Color?
        let compact: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var fill: AnyShapeStyle {
            if let tint { return AnyShapeStyle(tint) }
            return AnyShapeStyle(DustyTheme.brandGradient)
        }

        var body: some View {
            configuration.label
                .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: compact ? nil : .infinity)
                .padding(.horizontal, compact ? 14 : 16)
                .frame(height: compact ? 30 : 38)
                .background(
                    RoundedRectangle(cornerRadius: DustyTheme.controlRadius, style: .continuous)
                        .fill(fill)
                        .brightness(hovering && isEnabled ? 0.05 : 0)
                        .shadow(color: (tint ?? DustyTheme.azure).opacity(isEnabled ? (hovering ? 0.38 : 0.24) : 0),
                                radius: hovering ? 9 : 6, y: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DustyTheme.controlRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .saturation(isEnabled ? 1 : 0.2)
                .opacity(isEnabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(DustyTheme.pressSpring, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
                .contentShape(RoundedRectangle(cornerRadius: DustyTheme.controlRadius, style: .continuous))
        }
    }
}

/// Quiet button: an inset fill that wakes on hover. For secondary actions next
/// to a primary one (Cancel, Rescan, Review).
struct DustySecondaryButtonStyle: ButtonStyle {
    var fullWidth = false
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, fullWidth: fullWidth, tint: tint)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let fullWidth: Bool
        let tint: Color?
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var background: Color {
            let lit = hovering && isEnabled
            if let tint { return tint.opacity(lit ? 0.2 : 0.13) }
            return lit ? DustyTheme.insetHover : DustyTheme.inset
        }

        var body: some View {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint ?? Color.primary)
                .lineLimit(1)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, 14)
                .frame(height: fullWidth ? 38 : 30)
                .background(
                    RoundedRectangle(cornerRadius: DustyTheme.controlRadius, style: .continuous)
                        .fill(background)
                )
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(DustyTheme.pressSpring, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
                .contentShape(RoundedRectangle(cornerRadius: DustyTheme.controlRadius, style: .continuous))
        }
    }
}

/// Bare icon button (gear, back, close) with a hover halo.
struct DustyIconButtonStyle: ButtonStyle {
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, size: size)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .foregroundStyle(hovering && isEnabled ? Color.primary : Color.secondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering && isEnabled ? DustyTheme.insetHover : .clear)
                )
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
                .animation(DustyTheme.pressSpring, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// A whole list row as one button: a hover wash across the row, no chrome.
struct DustyRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .background(
                    Rectangle().fill(configuration.isPressed ? DustyTheme.insetHover
                                     : (hovering && isEnabled ? DustyTheme.inset : .clear))
                )
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// Text-only link button in the accent color.
struct DustyLinkButtonStyle: ButtonStyle {
    var tint: Color = DustyTheme.accent

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, tint: tint)
    }

    private struct StyledBody: View {
        let configuration: Configuration
        let tint: Color
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(tint)
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
                .underline(hovering && isEnabled, color: tint.opacity(0.5))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
