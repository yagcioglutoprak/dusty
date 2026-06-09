import XCTest
@testable import CleanerEngine

final class SelectionLogicTests: XCTestCase {
    func testSelectedBytesOnlyCountsSelectedPaths() {
        let target = CleanupTarget(
            id: "test",
            displayName: "Test",
            level: .deep,
            pathTemplates: ["~/Downloads"],
            category: "Test",
            requiresIndividualSelection: true
        )
        let paths = [
            ResolvedPath(path: "/a", displayName: "a", targetID: "test", estimatedBytes: 100, isSelected: true),
            ResolvedPath(path: "/b", displayName: "b", targetID: "test", estimatedBytes: 200, isSelected: false),
        ]
        let targetResult = TargetScanResult(target: target, resolvedPaths: paths)
        XCTAssertEqual(targetResult.selectedBytes, 100)
        XCTAssertEqual(targetResult.selectedCount, 1)
    }

    func testLevelScanResultHasSelection() {
        let target = CleanupTarget(id: "t", displayName: "T", level: .safe, pathTemplates: ["~/Library/Caches"], category: "C")
        let result = TargetScanResult(target: target, resolvedPaths: [
            ResolvedPath(path: "/x", displayName: "x", targetID: "t", estimatedBytes: 50, isSelected: false)
        ])
        let level = LevelScanResult(level: .safe, targetResults: [result])
        XCTAssertFalse(level.hasSelection)
        XCTAssertEqual(level.selectedBytes, 0)
    }

    func testEffectiveMoveToTrashOnlyForNonSafeLevels() {
        var options = CleanerOptions(moveToTrash: true, cleanupLevel: .safe)
        XCTAssertFalse(options.effectiveMoveToTrash)
        options.cleanupLevel = .developer
        XCTAssertTrue(options.effectiveMoveToTrash)
        options.cleanupLevel = .deep
        XCTAssertTrue(options.effectiveMoveToTrash)
    }

    func testTrashForUndoAppliesAtEveryLevel() {
        var options = CleanerOptions(cleanupLevel: .safe, trashForUndo: true)
        XCTAssertTrue(options.effectiveMoveToTrash)
        options.cleanupLevel = .developer
        XCTAssertTrue(options.effectiveMoveToTrash)
        options.cleanupLevel = .deep
        XCTAssertTrue(options.effectiveMoveToTrash)
        options.trashForUndo = false
        XCTAssertFalse(options.effectiveMoveToTrash, "Without the undo window or the Trash preference, deletes are permanent")
    }
}

final class PathTraversalTests: XCTestCase {
    var tempHome: URL!
    var validator: SafetyValidator!

    override func setUpWithError() throws {
        tempHome = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        validator = SafetyValidator(fileManager: .default, homeDirectory: tempHome, bootVolumeURL: tempHome)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempHome)
    }

    func testPathTraversalRejected() throws {
        let target = CleanupTargetRegistry.level1.first { $0.id == "user-caches" }!
        let cacheRoot = tempHome.appendingPathComponent("Library/Caches").path
        try FileManager.default.createDirectory(atPath: cacheRoot, withIntermediateDirectories: true)
        let evil = (cacheRoot as NSString).appendingPathComponent("nested/../..") + "/Documents/secret"
        let result = validator.validateDeletionPath(evil, for: target)
        if case .pathTraversal = result.error {
            // expected
        } else if case .prohibitedPath = result.error {
            // also acceptable after normalization
        } else {
            XCTFail("Expected pathTraversal or prohibitedPath, got \(String(describing: result.error))")
        }
    }
}
