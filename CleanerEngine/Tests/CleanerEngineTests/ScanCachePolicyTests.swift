import XCTest
@testable import CleanerEngine

/// The engine threads the sizing policy from `scan()` down to the per-item size calls,
/// so a background scan (`.cached`) reuses directory sizes while the interactive scan
/// (`.fresh`) always re-walks.
final class ScanCachePolicyTests: XCTestCase {
    var fileManager: FileManager!
    var tempHome: URL!
    var clock: Date!

    override func setUpWithError() throws {
        fileManager = FileManager.default
        tempHome = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempHome, withIntermediateDirectories: true)
        clock = Date(timeIntervalSince1970: 1_000_000)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: tempHome)
    }

    private func makeCachedEngine() -> CleanerEngine {
        let target = CleanupTargetRegistry.level1.first { $0.id == "user-caches" }!
        let validator = SafetyValidator(
            fileManager: fileManager, homeDirectory: tempHome,
            bootVolumeURL: tempHome, allowedTargets: [target]
        )
        let cache = SizeCache(ttl: 3600, now: { [weak self] in self?.clock ?? Date() })
        return CleanerEngine(
            fileManager: fileManager,
            validator: validator,
            sizeCalculator: SizeCalculator(fileManager: fileManager, cache: cache),
            diskMonitor: DiskSpaceMonitor(fileManager: fileManager),
            deletionLog: InMemoryDeletionLogStore()
        )
    }

    private func writeCacheChild(bytes: Int, pinnedMtime: Date) throws {
        let appDir = tempHome.appendingPathComponent("Library/Caches/app")
        try fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: bytes).write(to: appDir.appendingPathComponent("payload.bin"))
        try fileManager.setAttributes([.modificationDate: pinnedMtime], ofItemAtPath: appDir.path)
    }

    func testCachedScanReusesSizeWhileFreshScanRewalks() async throws {
        let pinned = Date(timeIntervalSince1970: 500_000)
        try writeCacheChild(bytes: 1024, pinnedMtime: pinned)
        let engine = makeCachedEngine()

        let first = await engine.scan(levels: [.safe], sizingPolicy: .cached)
        let t1 = first.levelResults[.safe]?.totalBytes ?? 0
        XCTAssertGreaterThan(t1, 0)

        // Grow the cached child but keep its mtime pinned.
        try writeCacheChild(bytes: 64 * 1024, pinnedMtime: pinned)

        let cached = await engine.scan(levels: [.safe], sizingPolicy: .cached)
        XCTAssertEqual(cached.levelResults[.safe]?.totalBytes, t1, "Cached scan must reuse the recorded size")

        let fresh = await engine.scan(levels: [.safe], sizingPolicy: .fresh)
        XCTAssertGreaterThan(fresh.levelResults[.safe]?.totalBytes ?? 0, t1, "Fresh scan must re-walk and see the growth")
    }

    func testScanStillReturnsAllRequestedLevelsUnderBoundedConcurrency() async throws {
        try writeCacheChild(bytes: 2048, pinnedMtime: Date(timeIntervalSince1970: 500_000))
        let engine = makeCachedEngine()

        let result = await engine.scan(levels: Set(CleanupLevel.allCases), sizingPolicy: .fresh)
        // Every requested level is present, proving the bounded scan covers all targets.
        for level in CleanupLevel.allCases {
            XCTAssertNotNil(result.levelResults[level], "Level \(level) must be present in the scan result")
        }
    }
}
