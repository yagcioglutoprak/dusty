import XCTest
@testable import CleanerEngine

/// The memory screen repeats Activity Monitor's split (app, wired, compressed,
/// cached files), so the arithmetic has to match it and must never report more
/// memory than the machine has.
final class MemoryStatsTests: XCTestCase {
    private let page: UInt64 = 16_384
    private let gib: Int64 = 1_073_741_824
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func pages(_ bytes: Int64) -> UInt64 { UInt64(bytes) / 16_384 }

    func testPressureReadsKernelLevels() {
        XCTAssertEqual(MemoryPressure(kernelLevel: 1), .normal)
        XCTAssertEqual(MemoryPressure(kernelLevel: 2), .warning)
        XCTAssertEqual(MemoryPressure(kernelLevel: 4), .critical)
        XCTAssertEqual(MemoryPressure(kernelLevel: 0), .normal, "Unknown levels never raise an alarm")
        XCTAssertEqual(MemoryPressure(kernelLevel: 99), .normal)
        XCTAssertLessThan(MemoryPressure.normal, .warning)
        XCTAssertLessThan(MemoryPressure.warning, .critical)
    }

    func testSnapshotSplitsLikeActivityMonitor() {
        let counts = VMPageCounts(
            free: pages(1 * gib),
            wired: pages(2 * gib),
            compressed: pages(1 * gib),
            purgeable: pages(gib / 2),
            fileBacked: pages(3 * gib),
            anonymous: pages(6 * gib)
        )
        let snapshot = MemorySnapshot.from(
            pages: counts, pageSize: page, totalBytes: 16 * gib,
            swapUsedBytes: gib, swapTotalBytes: 2 * gib, pressure: .normal, sampledAt: now
        )
        // App memory excludes the purgeable part; cached files include it.
        XCTAssertEqual(snapshot.appBytes, 6 * gib - gib / 2)
        XCTAssertEqual(snapshot.wiredBytes, 2 * gib)
        XCTAssertEqual(snapshot.compressedBytes, 1 * gib)
        XCTAssertEqual(snapshot.cachedFilesBytes, 3 * gib + gib / 2)
        XCTAssertEqual(snapshot.usedBytes, 8 * gib + gib / 2)
        XCTAssertEqual(snapshot.availableBytes, 7 * gib + gib / 2)
        XCTAssertEqual(snapshot.freeBytes, 4 * gib)
        XCTAssertEqual(snapshot.swapUsedBytes, gib)
        XCTAssertEqual(snapshot.usedFraction, 8.5 / 16, accuracy: 0.0001)
    }

    func testSnapshotNeverExceedsPhysicalMemory() {
        // A racing sample can add up to more than the machine has.
        let counts = VMPageCounts(wired: pages(6 * gib), compressed: pages(4 * gib),
                                  fileBacked: pages(8 * gib), anonymous: pages(10 * gib))
        let snapshot = MemorySnapshot.from(
            pages: counts, pageSize: page, totalBytes: 16 * gib,
            swapUsedBytes: 0, swapTotalBytes: 0, pressure: .critical, sampledAt: now
        )
        XCTAssertEqual(snapshot.wiredBytes, 6 * gib, "Wired memory is clamped last")
        XCTAssertLessThanOrEqual(snapshot.usedBytes + snapshot.cachedFilesBytes, snapshot.totalBytes)
        XCTAssertEqual(snapshot.availableBytes, 0)
        XCTAssertEqual(snapshot.freeBytes, 0)
        XCTAssertEqual(snapshot.usedFraction, 1)
    }

    func testPurgeableLargerThanAnonymousDoesNotGoNegative() {
        let counts = VMPageCounts(purgeable: pages(2 * gib), anonymous: pages(1 * gib))
        let snapshot = MemorySnapshot.from(
            pages: counts, pageSize: page, totalBytes: 8 * gib,
            swapUsedBytes: -5, swapTotalBytes: -5, pressure: .normal, sampledAt: now
        )
        XCTAssertEqual(snapshot.appBytes, 0)
        XCTAssertEqual(snapshot.swapUsedBytes, 0)
        XCTAssertEqual(snapshot.swapTotalBytes, 0)
    }

    func testHugePageCountsSaturateInsteadOfTrapping() {
        let counts = VMPageCounts(wired: .max, fileBacked: .max, anonymous: .max)
        let snapshot = MemorySnapshot.from(
            pages: counts, pageSize: .max, totalBytes: 16 * gib,
            swapUsedBytes: 0, swapTotalBytes: 0, pressure: .normal, sampledAt: now
        )
        XCTAssertEqual(snapshot.usedBytes, 16 * gib)
    }

    func testEmptyMachineReportsZeroFraction() {
        let snapshot = MemorySnapshot.from(
            pages: VMPageCounts(), pageSize: page, totalBytes: 0,
            swapUsedBytes: 0, swapTotalBytes: 0, pressure: .normal, sampledAt: now
        )
        XCTAssertEqual(snapshot.usedFraction, 0)
    }

    func testMemoryIsFormattedInBinaryUnits() {
        // A 16 GB Mac has 16 GiB. Decimal units would call it 17.18 GB.
        let text = MemorySnapshot.formatBytes(16 * gib)
        XCTAssertTrue(text.hasPrefix("16"), "Got \(text)")
        XCTAssertFalse(text.contains("17"), "Got \(text)")
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let snapshot = MemorySnapshot(
            totalBytes: 16 * gib, appBytes: 4 * gib, wiredBytes: 2 * gib, compressedBytes: gib,
            cachedFilesBytes: 3 * gib, swapUsedBytes: 0, swapTotalBytes: 0, pressure: .warning, sampledAt: now
        )
        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(MemorySnapshot.self, from: data), snapshot)
    }
}
