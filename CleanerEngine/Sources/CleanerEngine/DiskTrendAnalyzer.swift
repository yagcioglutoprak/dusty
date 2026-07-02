import Foundation

/// One free-space measurement. The app records one per day; the analyzer turns the
/// series into a fill-rate estimate.
public struct DiskSpaceSample: Codable, Sendable, Hashable {
    public let date: Date
    public let freeBytes: Int64

    public init(date: Date, freeBytes: Int64) {
        self.date = date
        self.freeBytes = freeBytes
    }
}

/// The disk's direction of travel: how fast free space is changing, and if it is
/// shrinking, roughly when it runs out.
public struct DiskForecast: Sendable, Hashable {
    /// Positive when the disk is filling up (free space shrinking).
    public let consumedBytesPerDay: Int64
    /// Days until free space hits zero at the current rate. Nil when free space is
    /// stable or growing.
    public let daysUntilFull: Double?

    public init(consumedBytesPerDay: Int64, daysUntilFull: Double?) {
        self.consumedBytesPerDay = consumedBytesPerDay
        self.daysUntilFull = daysUntilFull
    }
}

/// Least-squares fit over free-space samples. Pure and deterministic: the caller
/// supplies the samples and "now", nothing here touches the disk or the clock.
public enum DiskTrendAnalyzer {
    /// Minimum samples and time span before a trend is worth reporting. Anything
    /// less reads noise (one big download, one clean) as a trend.
    public static let minimumSamples = 5
    public static let minimumSpanDays = 3.0

    public static func forecast(samples: [DiskSpaceSample], now: Date) -> DiskForecast? {
        let sorted = samples.sorted { $0.date < $1.date }
        guard sorted.count >= minimumSamples,
              let first = sorted.first, let last = sorted.last else { return nil }

        let spanDays = last.date.timeIntervalSince(first.date) / 86400
        guard spanDays >= minimumSpanDays else { return nil }

        // Least squares of freeBytes over days-since-first-sample.
        let points = sorted.map { sample in
            (x: sample.date.timeIntervalSince(first.date) / 86400, y: Double(sample.freeBytes))
        }
        let n = Double(points.count)
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        let sumXY = points.reduce(0) { $0 + $1.x * $1.y }
        let sumXX = points.reduce(0) { $0 + $1.x * $1.x }
        let denominator = n * sumXX - sumX * sumX
        guard denominator != 0 else { return nil }

        let slope = (n * sumXY - sumX * sumY) / denominator // bytes of free space per day
        let consumedPerDay = Int64(-slope.rounded())

        guard consumedPerDay > 0 else {
            return DiskForecast(consumedBytesPerDay: consumedPerDay, daysUntilFull: nil)
        }

        let currentFree = Double(last.freeBytes)
        let days = currentFree / Double(consumedPerDay)
        return DiskForecast(consumedBytesPerDay: consumedPerDay, daysUntilFull: days)
    }

    /// Keeps at most one sample per calendar day (the latest wins) and drops samples
    /// older than `keepDays`. The app calls this before persisting.
    public static func compact(samples: [DiskSpaceSample], keepDays: Int, now: Date) -> [DiskSpaceSample] {
        let cutoff = now.addingTimeInterval(-Double(keepDays) * 86400)
        var byDay: [Int: DiskSpaceSample] = [:]
        for sample in samples where sample.date >= cutoff {
            let day = Int(sample.date.timeIntervalSinceReferenceDate / 86400)
            if let existing = byDay[day], existing.date > sample.date { continue }
            byDay[day] = sample
        }
        return byDay.values.sorted { $0.date < $1.date }
    }
}
