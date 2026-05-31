import XCTest
@testable import CleanerEngine

final class CleaningAuditTests: XCTestCase {
    var fm: FileManager!
    var tempHome: URL!

    override func setUpWithError() throws {
        fm = FileManager.default
        tempHome = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tempHome)
    }

    func testSizeCountsHiddenFiles() throws {
        let dir = tempHome.appendingPathComponent("cache", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 4096).write(to: dir.appendingPathComponent(".hidden"))

        // Before the fix this returned 0 because hidden files were skipped.
        XCTAssertGreaterThan(SizeCalculator(fileManager: fm).allocatedSize(at: dir.path), 0)
    }

    func testOldInstallersFilteredByAge() throws {
        let downloads = tempHome.appendingPathComponent("Downloads", isDirectory: true)
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)

        let old = downloads.appendingPathComponent("old.dmg")
        let recent = downloads.appendingPathComponent("recent.dmg")
        try Data(count: 16).write(to: old)
        try Data(count: 16).write(to: recent)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-60 * 86400)], ofItemAtPath: old.path)

        let target = CleanupTargetRegistry.level3.first { $0.id == "downloads-installers" }!
        let validator = SafetyValidator(fileManager: fm, homeDirectory: tempHome, allowedTargets: [target])
        let resolved = validator.resolveAllowlistedPaths(for: target)

        XCTAssertTrue(resolved.contains(old.path))
        XCTAssertFalse(resolved.contains(recent.path))
    }
}
