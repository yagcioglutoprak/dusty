import Foundation
import CleanerEngine

/// Persists one free-space sample per day so DiskTrendAnalyzer has a series to
/// fit. UserDefaults-backed: thirty numbers, not worth a file format.
final class DiskHistoryStore {
    static let shared = DiskHistoryStore()

    private static let defaultsKey = "diskSpaceHistory"
    private static let keepDays = 30
    /// Recording more than every few hours adds nothing to a per-day series.
    private static let minimumSampleGap: TimeInterval = 4 * 3600

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private(set) lazy var samples: [DiskSpaceSample] = load()

    /// Records a sample unless one was taken recently. Returns true when the
    /// series changed (a new forecast is worth computing).
    @discardableResult
    func record(freeBytes: Int64, now: Date = Date()) -> Bool {
        guard freeBytes > 0 else { return false }
        if let last = samples.last, now.timeIntervalSince(last.date) < Self.minimumSampleGap {
            return false
        }
        samples.append(DiskSpaceSample(date: now, freeBytes: freeBytes))
        samples = DiskTrendAnalyzer.compact(samples: samples, keepDays: Self.keepDays, now: now)
        save()
        return true
    }

    func forecast(now: Date = Date()) -> DiskForecast? {
        DiskTrendAnalyzer.forecast(samples: samples, now: now)
    }

    private func load() -> [DiskSpaceSample] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([DiskSpaceSample].self, from: data)
        else { return [] }
        return decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(samples) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
