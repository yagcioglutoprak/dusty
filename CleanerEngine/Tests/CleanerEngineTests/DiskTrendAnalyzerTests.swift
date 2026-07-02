import XCTest
@testable import CleanerEngine

/// The forecast is a least-squares fit over daily free-space samples. It must stay
/// quiet on thin or short data (noise is not a trend) and must never report a
/// "days until full" for a disk that is not filling up.
final class DiskTrendAnalyzerTests: XCTestCase {
    private let day: TimeInterval = 86400
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func samples(_ freeByDay: [Int64]) -> [DiskSpaceSample] {
        // Oldest first; the last sample lands on `now`.
        freeByDay.enumerated().map { index, free in
            DiskSpaceSample(
                date: now.addingTimeInterval(-Double(freeByDay.count - 1 - index) * day),
                freeBytes: free
            )
        }
    }

    func testTooFewSamplesGiveNoForecast() {
        XCTAssertNil(DiskTrendAnalyzer.forecast(samples: samples([100, 90, 80, 70]), now: now))
    }

    func testTooShortASpanGivesNoForecast() {
        let cramped = (0..<6).map { i in
            DiskSpaceSample(date: now.addingTimeInterval(Double(i) * 3600), freeBytes: 100 - Int64(i))
        }
        XCTAssertNil(DiskTrendAnalyzer.forecast(samples: cramped, now: now))
    }

    func testSteadyConsumptionForecastsDaysUntilFull() throws {
        // Losing 10 GB/day, 60 GB free at the last sample.
        let gb: Int64 = 1_000_000_000
        let forecast = try XCTUnwrap(DiskTrendAnalyzer.forecast(
            samples: samples([100 * gb, 90 * gb, 80 * gb, 70 * gb, 60 * gb]),
            now: now
        ))
        XCTAssertEqual(forecast.consumedBytesPerDay, 10 * gb)
        XCTAssertEqual(try XCTUnwrap(forecast.daysUntilFull), 6.0, accuracy: 0.01)
    }

    func testGrowingFreeSpaceHasNoDaysUntilFull() throws {
        let forecast = try XCTUnwrap(DiskTrendAnalyzer.forecast(
            samples: samples([60, 70, 80, 90, 100]),
            now: now
        ))
        XCTAssertNil(forecast.daysUntilFull, "A disk gaining space is never 'about to fill up'")
        XCTAssertLessThan(forecast.consumedBytesPerDay, 0)
    }

    func testFlatDiskHasNoDaysUntilFull() throws {
        let forecast = try XCTUnwrap(DiskTrendAnalyzer.forecast(
            samples: samples([50, 50, 50, 50, 50]),
            now: now
        ))
        XCTAssertNil(forecast.daysUntilFull)
    }

    func testUnsortedSamplesFitTheSameLine() throws {
        let ordered = samples([100, 90, 80, 70, 60])
        let shuffled = [ordered[3], ordered[0], ordered[4], ordered[1], ordered[2]]
        XCTAssertEqual(
            DiskTrendAnalyzer.forecast(samples: shuffled, now: now),
            DiskTrendAnalyzer.forecast(samples: ordered, now: now)
        )
    }

    func testCompactKeepsOneSamplePerDayAndDropsOldOnes() {
        let old = DiskSpaceSample(date: now.addingTimeInterval(-40 * day), freeBytes: 1)
        let morning = DiskSpaceSample(date: now.addingTimeInterval(-day), freeBytes: 2)
        let evening = DiskSpaceSample(date: now.addingTimeInterval(-day + 3600), freeBytes: 3)
        let today = DiskSpaceSample(date: now, freeBytes: 4)

        let compacted = DiskTrendAnalyzer.compact(
            samples: [old, morning, evening, today], keepDays: 30, now: now
        )
        XCTAssertEqual(compacted, [evening, today], "Latest sample of each day wins, old ones drop")
    }
}
