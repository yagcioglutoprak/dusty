import SwiftUI
import CleanerEngine

/// What the scan noticed, said out loud: a disk filling up, data orphaned by an
/// uninstalled tool, a cache nothing has touched in months. Read-only by design;
/// the levels below stay the only place anything gets selected or cleaned.
struct InsightsCard: View {
    let forecast: DiskForecast?
    let advisories: [Advisory]

    /// Beyond this the fit is noise, not news.
    private static let forecastHorizonDays = 90.0
    /// The card shows at most this many advisories, biggest first.
    private static let maxAdvisories = 3

    private var forecastLine: (text: String, tint: Color)? {
        guard let forecast, let days = forecast.daysUntilFull,
              days <= Self.forecastHorizonDays else { return nil }
        let tint: Color = days < 14 ? DustyTheme.danger : DustyTheme.warn
        return ("\(Self.horizonLabel(days: days)) until the disk fills at the current rate "
                + "(\(DiskSpaceMonitor.formatBytes(forecast.consumedBytesPerDay))/day).", tint)
    }

    private var shownAdvisories: [Advisory] {
        Array(advisories.prefix(Self.maxAdvisories))
    }

    var body: some View {
        if forecastLine != nil || !shownAdvisories.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.max.fill")
                        .font(.caption)
                        .foregroundStyle(DustyTheme.gold)
                        .accessibilityHidden(true)
                    Text("Insights")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                        .textCase(.uppercase)
                }

                if let line = forecastLine {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(line.tint)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(line.text)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }

                ForEach(shownAdvisories) { advisory in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: advisory.id.hasPrefix("orphan-") ? "archivebox" : "zzz")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DustyTheme.info)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(advisory.title)
                                    .font(.footnote.weight(.semibold))
                                Spacer(minLength: 8)
                                Text(DiskSpaceMonitor.formatBytes(advisory.bytes))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(advisory.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dustyCard()
        }
    }

    /// "About 5 days" / "About 3 weeks" / "About 2 months": rough on purpose, a
    /// linear fit does not deserve false precision.
    static func horizonLabel(days: Double) -> String {
        switch days {
        case ..<1: return "Less than a day"
        case ..<14: return "About \(max(1, Int(days.rounded()))) day\(Int(days.rounded()) == 1 ? "" : "s")"
        case ..<56: return "About \(Int((days / 7).rounded())) weeks"
        default: return "About \(Int((days / 30).rounded())) months"
        }
    }
}
