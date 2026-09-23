import SwiftUI
import CleanerEngine

/// What the scan noticed, said out loud: a disk filling up, data orphaned by an
/// uninstalled tool, a cache nothing has touched in months. Each advisory is a
/// link to the target it is about; nothing here selects or deletes anything.
struct InsightsSection: View {
    let forecast: DiskForecast?
    let advisories: [Advisory]
    let onSelect: (Advisory) -> Void

    /// Beyond this the fit is noise, not news.
    private static let forecastHorizonDays = 90.0
    /// At most this many advisories, biggest first.
    private static let maxAdvisories = 3

    private var forecastLine: (text: String, tint: Color)? {
        guard let forecast, let days = forecast.daysUntilFull,
              days <= Self.forecastHorizonDays else { return nil }
        let tint: Color = days < 14 ? DustyTheme.danger : DustyTheme.warn
        let text = L10n.f("insights.forecast", "%1$@ until the disk fills at the current rate (%2$@/day).",
                          Self.horizonLabel(days: days),
                          Bytes.format(forecast.consumedBytesPerDay))
        return (text, tint)
    }

    private var shown: [Advisory] {
        Array(advisories.prefix(Self.maxAdvisories))
    }

    var body: some View {
        if forecastLine != nil || !shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: L10n.t("insights.title", "Insights"))
                VStack(spacing: 0) {
                    if let line = forecastLine {
                        forecastRow(line.text, tint: line.tint)
                        if !shown.isEmpty { Hairline(leading: 52) }
                    }
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, advisory in
                        advisoryRow(advisory)
                        if index < shown.count - 1 { Hairline(leading: 52) }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DustyTheme.cardRadius, style: .continuous))
                .dustyCard()
            }
        }
    }

    private func forecastRow(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: "chart.line.downtrend.xyaxis", tint: tint, size: 28, style: .soft)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func advisoryRow(_ advisory: Advisory) -> some View {
        Button {
            onSelect(advisory)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                IconTile(symbol: advisory.id.hasPrefix("orphan-") ? "shippingbox" : "moon.zzz",
                         tint: DustyTheme.accent, size: 28, style: .soft)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(advisory.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Bytes.format(advisory.bytes))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(advisory.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DustyTheme.faint)
                    .padding(.top, 3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(DustyRowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.t("insights.a11y.hint", "Opens the level that holds this item"))
    }

    /// "About 5 days" / "About 3 weeks" / "About 2 months": rough on purpose, a
    /// linear fit does not deserve false precision.
    static func horizonLabel(days: Double) -> String {
        switch days {
        case ..<1: return L10n.t("insights.horizon.lessThanDay", "Less than a day")
        case ..<14: return L10n.f("insights.horizon.days", "About %d days", max(1, Int(days.rounded())))
        case ..<56: return L10n.f("insights.horizon.weeks", "About %d weeks", Int((days / 7).rounded()))
        default: return L10n.f("insights.horizon.months", "About %d months", Int((days / 30).rounded()))
        }
    }
}
