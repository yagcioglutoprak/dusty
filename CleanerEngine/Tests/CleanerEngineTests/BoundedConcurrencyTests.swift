import XCTest
@testable import CleanerEngine

/// `runBounded` is the gentle replacement for the unbounded scan TaskGroup: it caps
/// how many directory walks run at once so a background scan does not saturate the disk.
final class BoundedConcurrencyTests: XCTestCase {
    actor ConcurrencyProbe {
        private(set) var current = 0
        private(set) var peak = 0
        func enter() { current += 1; peak = max(peak, current) }
        func leave() { current -= 1 }
    }

    func testNeverExceedsConcurrencyCap() async {
        let items = Array(0..<24)
        let probe = ConcurrencyProbe()

        let results = await runBounded(items, maxConcurrent: 4) { item in
            await probe.enter()
            try? await Task.sleep(nanoseconds: 1_000_000)
            await probe.leave()
            return item * 2
        }

        let peak = await probe.peak
        XCTAssertLessThanOrEqual(peak, 4, "Peak in-flight count must not exceed the cap")
        XCTAssertGreaterThan(peak, 1, "Sanity: work should actually run concurrently")
        XCTAssertEqual(results, items.map { $0 * 2 }, "All items processed, input order preserved")
    }

    func testPreservesInputOrder() async {
        let items = ["a", "b", "c", "d", "e"]
        let results = await runBounded(items, maxConcurrent: 2) { $0.uppercased() }
        XCTAssertEqual(results, ["A", "B", "C", "D", "E"])
    }

    func testEmptyInputReturnsEmpty() async {
        let results = await runBounded([Int](), maxConcurrent: 4) { $0 }
        XCTAssertTrue(results.isEmpty)
    }

    func testFewerItemsThanCapStillProcessesAll() async {
        let results = await runBounded([1, 2], maxConcurrent: 8) { $0 + 100 }
        XCTAssertEqual(results, [101, 102])
    }
}
