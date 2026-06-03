import XCTest
@testable import CleanerEngine

/// The size cache lets background scans skip re-walking unchanged directories.
/// Contract:
/// - `.cached` returns the recorded size while the directory's modification date is
///   unchanged AND the entry is younger than the TTL.
/// - `.cached` re-walks when the directory's mtime changes or the TTL has elapsed.
/// - `.fresh` always re-walks and refreshes the cache.
/// The TTL backstop exists because a directory's mtime does not change when a deeply
/// nested file grows, so mtime alone can be stale.
final class SizeCacheTests: XCTestCase {
    var fileManager: FileManager!
    var tempDir: URL!
    var clock: Date!

    override func setUpWithError() throws {
        fileManager = FileManager.default
        tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        clock = Date(timeIntervalSince1970: 1_000_000)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: tempDir)
    }

    private func makeCalculator(ttl: TimeInterval = 3600) -> SizeCalculator {
        let cache = SizeCache(ttl: ttl, now: { [weak self] in self?.clock ?? Date() })
        return SizeCalculator(fileManager: fileManager, cache: cache)
    }

    /// Write `bytes` to `dir/payload.bin`, then force the directory's modification date
    /// back to `pinnedMtime` so the test does not depend on filesystem mtime quirks.
    @discardableResult
    private func writePayload(_ bytes: Int, into dir: URL, pinnedMtime: Date) throws -> URL {
        let file = dir.appendingPathComponent("payload.bin")
        try Data(repeating: 0xAB, count: bytes).write(to: file)
        try fileManager.setAttributes([.modificationDate: pinnedMtime], ofItemAtPath: dir.path)
        return file
    }

    func testCachedPolicyReturnsRecordedSizeWhileMtimeUnchanged() throws {
        let pinned = Date(timeIntervalSince1970: 500_000)
        try writePayload(1024, into: tempDir, pinnedMtime: pinned)
        let calc = makeCalculator()

        let first = calc.allocatedSize(at: tempDir.path, policy: .cached)
        XCTAssertGreaterThan(first, 0)

        // Grow the file but keep the directory's mtime pinned: a cached read must NOT see it.
        try writePayload(64 * 1024, into: tempDir, pinnedMtime: pinned)

        let cached = calc.allocatedSize(at: tempDir.path, policy: .cached)
        XCTAssertEqual(cached, first, "Cached read must return the recorded size while dir mtime is unchanged")
    }

    func testFreshPolicyAlwaysRewalks() throws {
        let pinned = Date(timeIntervalSince1970: 500_000)
        try writePayload(1024, into: tempDir, pinnedMtime: pinned)
        let calc = makeCalculator()

        let first = calc.allocatedSize(at: tempDir.path, policy: .cached)
        try writePayload(64 * 1024, into: tempDir, pinnedMtime: pinned)

        let fresh = calc.allocatedSize(at: tempDir.path, policy: .fresh)
        XCTAssertGreaterThan(fresh, first, "Fresh read must always re-walk and see the larger size")
    }

    func testCachedPolicyRewalksWhenDirectoryMtimeChanges() throws {
        try writePayload(1024, into: tempDir, pinnedMtime: Date(timeIntervalSince1970: 500_000))
        let calc = makeCalculator()

        let first = calc.allocatedSize(at: tempDir.path, policy: .cached)

        // Grow the file AND advance the directory's mtime: cache must invalidate.
        try writePayload(64 * 1024, into: tempDir, pinnedMtime: Date(timeIntervalSince1970: 600_000))

        let recomputed = calc.allocatedSize(at: tempDir.path, policy: .cached)
        XCTAssertGreaterThan(recomputed, first, "A changed dir mtime must force a re-walk")
    }

    func testCachedPolicyRewalksAfterTTLExpires() throws {
        let pinned = Date(timeIntervalSince1970: 500_000)
        try writePayload(1024, into: tempDir, pinnedMtime: pinned)
        let calc = makeCalculator(ttl: 3600)

        let first = calc.allocatedSize(at: tempDir.path, policy: .cached)

        // Same dir mtime, but grow the payload and let the TTL elapse.
        try writePayload(64 * 1024, into: tempDir, pinnedMtime: pinned)
        clock = clock.addingTimeInterval(3601)

        let recomputed = calc.allocatedSize(at: tempDir.path, policy: .cached)
        XCTAssertGreaterThan(recomputed, first, "An expired TTL must force a re-walk even when mtime is unchanged")
    }

    func testCacheWithoutInjectionDefaultsToFreshBehavior() throws {
        let pinned = Date(timeIntervalSince1970: 500_000)
        try writePayload(1024, into: tempDir, pinnedMtime: pinned)
        // No cache injected: every read re-walks regardless of policy.
        let calc = SizeCalculator(fileManager: fileManager)

        let first = calc.allocatedSize(at: tempDir.path, policy: .cached)
        try writePayload(64 * 1024, into: tempDir, pinnedMtime: pinned)
        let second = calc.allocatedSize(at: tempDir.path, policy: .cached)
        XCTAssertGreaterThan(second, first, "With no cache, even a cached-policy read must re-walk")
    }
}
