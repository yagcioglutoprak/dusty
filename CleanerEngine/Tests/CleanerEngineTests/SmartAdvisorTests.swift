import XCTest
@testable import CleanerEngine

/// Advisories point at orphaned tool data and long-untouched caches. They must stay
/// quiet for small amounts, for installed tools, and for anything recently written,
/// and they must never select or delete anything themselves.
final class SmartAdvisorTests: XCTestCase {
    var fileManager: FileManager!
    var tempRoot: URL!
    var applications: URL!
    var binDir: URL!

    private let gigabyte: Int64 = 1_000_000_000
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUpWithError() throws {
        fileManager = FileManager.default
        tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        applications = tempRoot.appendingPathComponent("Applications")
        binDir = tempRoot.appendingPathComponent("bin")
        try fileManager.createDirectory(at: applications, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: binDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: tempRoot)
    }

    private func advisor() -> SmartAdvisor {
        SmartAdvisor(
            fileManager: fileManager,
            applicationsDirectory: applications.path,
            binaryDirectories: [binDir.path]
        )
    }

    private func target(_ id: String) -> CleanupTarget {
        CleanupTargetRegistry.all.first { $0.id == id }!
    }

    /// A scan result whose paths live under tempRoot with a controlled mtime.
    private func scanResult(
        targetID: String,
        bytes: Int64,
        ageDays: Int
    ) throws -> TargetScanResult {
        let dir = tempRoot.appendingPathComponent("data-\(targetID)", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = now.addingTimeInterval(-Double(ageDays) * 86400)
        try fileManager.setAttributes([.modificationDate: stamp], ofItemAtPath: dir.path)
        let resolved = ResolvedPath(
            path: dir.path,
            displayName: dir.lastPathComponent,
            targetID: targetID,
            estimatedBytes: bytes,
            lastModified: stamp
        )
        return TargetScanResult(target: target(targetID), resolvedPaths: [resolved])
    }

    private func scan(_ results: [TargetScanResult], level: CleanupLevel = .developer) -> FullScanResult {
        FullScanResult(levelResults: [level: LevelScanResult(level: level, targetResults: results)])
    }

    // MARK: - Orphaned tool data

    func testXcodeDataWithoutXcodeIsFlagged() throws {
        let result = try scanResult(targetID: "xcode-derived-data", bytes: 12 * gigabyte, ageDays: 5)
        let advisories = advisor().advisories(for: scan([result]), now: now)
        XCTAssertEqual(advisories.count, 1)
        XCTAssertEqual(advisories.first?.id, "orphan-xcode-derived-data")
        XCTAssertEqual(advisories.first?.targetID, "xcode-derived-data")
    }

    func testXcodeDataWithXcodeInstalledIsNotFlagged() throws {
        try fileManager.createDirectory(
            at: applications.appendingPathComponent("Xcode.app"), withIntermediateDirectories: true)
        let result = try scanResult(targetID: "xcode-derived-data", bytes: 12 * gigabyte, ageDays: 5)
        XCTAssertTrue(advisor().advisories(for: scan([result]), now: now).isEmpty)
    }

    func testBetaXcodeCountsAsInstalled() throws {
        try fileManager.createDirectory(
            at: applications.appendingPathComponent("Xcode-beta.app"), withIntermediateDirectories: true)
        let result = try scanResult(targetID: "xcode-derived-data", bytes: 12 * gigabyte, ageDays: 5)
        XCTAssertTrue(advisor().advisories(for: scan([result]), now: now).isEmpty)
    }

    func testOllamaModelsWithoutOllamaAreFlaggedAndBinaryCountsAsInstalled() throws {
        let result = try scanResult(targetID: "ollama-models", bytes: 20 * gigabyte, ageDays: 10)
        XCTAssertEqual(advisor().advisories(for: scan([result], level: .deep), now: now).first?.id,
                       "orphan-ollama-models")

        fileManager.createFile(atPath: binDir.appendingPathComponent("ollama").path, contents: Data())
        XCTAssertTrue(advisor().advisories(for: scan([result], level: .deep), now: now).isEmpty)
    }

    func testSmallOrphanedDataIsNotWorthAnAdvisory() throws {
        let result = try scanResult(targetID: "xcode-derived-data", bytes: 5_000_000, ageDays: 5)
        XCTAssertTrue(advisor().advisories(for: scan([result]), now: now).isEmpty)
    }

    // MARK: - Untouched caches

    func testBigOldCacheIsFlaggedAsUntouched() throws {
        let result = try scanResult(targetID: "gradle-cache", bytes: 3 * gigabyte, ageDays: 120)
        let advisories = advisor().advisories(for: scan([result]), now: now)
        XCTAssertEqual(advisories.first?.id, "stale-gradle-cache")
        XCTAssertTrue(advisories.first?.title.contains("120 days") == true)
    }

    func testRecentlyTouchedCacheIsNotFlagged() throws {
        let result = try scanResult(targetID: "gradle-cache", bytes: 3 * gigabyte, ageDays: 10)
        XCTAssertTrue(advisor().advisories(for: scan([result]), now: now).isEmpty)
    }

    func testDeepRecentFileKillsAShallowStaleAdvisory() throws {
        // The root dir looks 120 days old, but a file deep inside was written
        // yesterday. The bounded walk must find it and stay quiet.
        let result = try scanResult(targetID: "gradle-cache", bytes: 3 * gigabyte, ageDays: 120)
        let root = URL(fileURLWithPath: result.resolvedPaths[0].path)
        let deep = root.appendingPathComponent("modules/files/recent.bin")
        try fileManager.createDirectory(at: deep.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileManager.createFile(atPath: deep.path, contents: Data())
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-86400)], ofItemAtPath: deep.path)
        // Restore the old-looking root mtime that creating subdirs just bumped.
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-120 * 86400)], ofItemAtPath: root.path)

        XCTAssertTrue(advisor().advisories(for: scan([result]), now: now).isEmpty)
    }

    func testNonRegeneratingTargetsNeverGetStaleAdvisories() throws {
        // Xcode archives are old by nature; age is not a signal there.
        try fileManager.createDirectory(
            at: applications.appendingPathComponent("Xcode.app"), withIntermediateDirectories: true)
        let result = try scanResult(targetID: "xcode-archives", bytes: 30 * gigabyte, ageDays: 300)
        XCTAssertTrue(advisor().advisories(for: scan([result], level: .deep), now: now).isEmpty)
    }

    func testAdvisoriesSortBiggestFirst() throws {
        let small = try scanResult(targetID: "gradle-cache", bytes: 1 * gigabyte, ageDays: 100)
        let big = try scanResult(targetID: "xcode-derived-data", bytes: 15 * gigabyte, ageDays: 5)
        let advisories = advisor().advisories(for: scan([small, big]), now: now)
        XCTAssertEqual(advisories.map(\.targetID), ["xcode-derived-data", "gradle-cache"])
    }
}
