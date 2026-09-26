import SwiftUI
import CleanerEngine

// Small building blocks shared by every screen. Everything here is drawn in
// SwiftUI (no AppKit-backed controls) so it looks identical in light and dark,
// at any scale, and in the rendered snapshots.

/// The app icon in miniature: the brand gradient with a large and a small sparkle.
struct BrandMark: View {
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(DustyTheme.brandGradient)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.5, weight: .semibold))
                .offset(x: -size * 0.05, y: size * 0.06)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.2, weight: .bold))
                .offset(x: size * 0.23, y: -size * 0.21)
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .shadow(color: DustyTheme.azure.opacity(0.32), radius: size * 0.2, y: size * 0.06)
        .accessibilityHidden(true)
    }
}

/// An SF Symbol on a rounded tile, System Settings style. `solid` fills the
/// tile with the tint and draws the glyph white; `soft` washes the tile and
/// draws the glyph in the tint.
struct IconTile: View {
    enum Style { case solid, soft }

    let symbol: String
    let tint: Color
    var size: CGFloat = 30
    var style: Style = .solid

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(style == .solid ? tint : tint.opacity(0.14))
            if style == .solid {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.22), .clear],
                                         startPoint: .top, endPoint: .bottom))
            }
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(style == .solid ? Color.white : tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Small uppercase label above a group of cards, with an optional figure on
/// the right.
struct SectionHeader: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DustyTheme.faint)
                .textCase(.uppercase)
                .tracking(0.6)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(DustyTheme.faint)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A colored dot and a short label on a tinted capsule.
struct StatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.13)))
    }
}

/// A horizontal storage bar, macOS Storage settings style: colored segments in
/// order from the left, the remainder shown as the empty track.
struct CapacityBar: View {
    struct Segment: Identifiable {
        let id: String
        /// Share of the whole bar, 0...1.
        let fraction: Double
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    if segment.fraction > 0 {
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(3, geo.size.width * CGFloat(min(1, segment.fraction))))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Capsule().fill(DustyTheme.inset))
        .clipShape(Capsule())
        .animation(DustyTheme.revealSpring, value: segments.map(\.fraction))
    }
}

/// Legend entry for the storage bar.
struct LegendItem: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// Determinate progress on a slim capsule.
struct ProgressCapsule: View {
    let fraction: Double
    var fill: AnyShapeStyle = AnyShapeStyle(DustyTheme.brandGradient)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DustyTheme.inset)
                Capsule()
                    .fill(fill)
                    .frame(width: max(6, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.25), value: fraction)
    }
}

/// Indeterminate spinner that takes any tint (the system one cannot be drawn
/// white on a colored button). Driven by the clock rather than a repeating
/// animation, so it never drifts when its container moves.
struct Spinner: View {
    var tint: Color = .secondary
    var size: CGFloat = 14

    var body: some View {
        TimelineView(.animation) { context in
            let period = 0.9
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            Circle()
                .trim(from: 0.1, to: 0.78)
                .stroke(tint, style: StrokeStyle(lineWidth: max(1.5, size / 7), lineCap: .round))
                .rotationEffect(.degrees(phase * 360))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A ring that empties as a deadline approaches: the undo window, made visible.
struct CountdownRing: View {
    let deadline: Date
    let duration: TimeInterval
    var tint: Color = DustyTheme.accent
    var size: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
            let remaining = max(0, deadline.timeIntervalSince(context.date))
            let fraction = duration > 0 ? remaining / duration : 0
            ZStack {
                Circle().stroke(tint.opacity(0.22), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Selection state for a checkbox that can stand for a group.
enum CheckState {
    case on, off, mixed

    init(selected: Int, total: Int) {
        if selected == 0 { self = .off }
        else if selected >= total { self = .on }
        else { self = .mixed }
    }
}

/// A drawn checkbox with a mixed state for groups.
struct DustyCheckbox: View {
    let state: CheckState
    var tint: Color = DustyTheme.accent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(state == .off ? Color.clear : tint)
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .strokeBorder(state == .off ? DustyTheme.faint.opacity(0.75) : Color.clear, lineWidth: 1.25)
            if state != .off {
                Image(systemName: state == .on ? "checkmark" : "minus")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 16, height: 16)
        .animation(.easeOut(duration: 0.12), value: state)
        .accessibilityHidden(true)
    }
}

/// Top bar for pushed screens: a back button, a title, and optional trailing
/// controls. Esc goes back.
struct NavHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(DustyIconButtonStyle())
            .keyboardShortcut(.cancelAction)
            .help(L10n.t("nav.back", "Back"))
            .accessibilityLabel(L10n.t("nav.back", "Back"))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
    }
}

extension NavHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, onBack: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, onBack: onBack) { EmptyView() }
    }
}

/// A tinted, full-width message with an optional action and close button.
struct InlineBanner: View {
    let symbol: String
    let tint: Color
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(DustySecondaryButtonStyle(tint: tint))
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(DustyIconButtonStyle(size: 22))
                .accessibilityLabel(L10n.t("common.dismiss", "Dismiss"))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dustyCallout(tint: tint)
    }
}

/// A centered icon, headline, and message for screens with nothing to list.
struct EmptyStateView: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(tint.opacity(0.12)).frame(width: 56, height: 56)
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

/// A one-pixel divider in the hairline color, inset to line up with row text.
struct Hairline: View {
    var leading: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(DustyTheme.hairline)
            .frame(height: 1)
            .padding(.leading, leading)
    }
}

// MARK: - Formatting

enum Bytes {
    static func format(_ bytes: Int64) -> String {
        bytes > 0 ? DiskSpaceMonitor.formatBytes(bytes) : zero
    }

    /// RAM in binary units, so a 16 GB Mac reads 16 GB rather than 17.18.
    static func memory(_ bytes: Int64) -> String {
        bytes > 0 ? MemorySnapshot.formatBytes(bytes) : zero
    }

    /// "0 MB" rather than the formatter's spelled-out "Zero KB".
    private static let zero: String = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB]
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: 0)
    }()
}
