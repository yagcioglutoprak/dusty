import XCTest
@testable import CleanerEngine

/// Restore must validate both sides of the move: the source has to live inside the
/// user's Trash, and the destination has to pass SafetyValidator against the entry's
/// recorded cleanup target. These tests pin that down with crafted entries, the same
/// way a malicious or stale deletion-log line would look to the engine.
final class RestoreValidationTests: XCTestCase {
    var tempHome: URL!
    var fileManager: FileManager!
    var trashDir: URL!
    var cacheTarget: CleanupTarget!

    override func setUpWithError() throws {
        fileManager = FileManager.default
        tempHome = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        trashDir = tempHome.appendingPathComponent(".Trash")
        try fileManager.createDirectory(at: trashDir, withIntermediateDirectories: true)
        cacheTarget = CleanupTargetRegistry.level1.first { $0.id == "user-caches" }!
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: tempHome)
    }

    private func makeEngine() -> CleanerEngine {
        let validator = SafetyValidator(
            fileManager: fileManager,
            homeDirectory: tempHome,
            bootVolumeURL: tempHome,
            allowedTargets: CleanupTargetRegistry.all
        )
        return CleanerEngine(
            fileManager: fileManager,
            validator: validator,
            sizeCalculator: SizeCalculator(fileManager: fileManager),
            diskMonitor: DiskSpaceMonitor(fileManager: fileManager),
            deletionLog: InMemoryDeletionLogStore(),
            homeDirectory: tempHome
        )
    }

    private func stageTrashedFile(named name: String) throws -> URL {
        let trashed = trashDir.appendingPathComponent(name)
        try Data("payload".utf8).write(to: trashed)
        return trashed
    }

    func testRestoreMovesValidEntryBack() throws {
        let trashed = try stageTrashedFile(named: "junk.bin")
        let dest = tempHome.appendingPathComponent("Library/Caches/com.app/junk.bin")
        let entry = DeletionEntry(
            path: dest.path, bytes: 7, movedToTrash: true, dryRun: false,
            trashedPath: trashed.path, targetID: cacheTarget.id
        )

        let result = makeEngine().restore([entry])

        XCTAssertEqual(result.restoredCount, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(fileManager.fileExists(atPath: dest.path), "File must be back at its origin")
        XCTAssertFalse(fileManager.fileExists(atPath: trashed.path), "Trashed copy must be gone")
    }

    func testRestoreRefusesDestinationOutsideAllowlist() throws {
        let trashed = try stageTrashedFile(named: "evil.plist")
        // A crafted entry pointing the restore at LaunchAgents instead of a cache path.
        let dest = tempHome.appendingPathComponent("Library/LaunchAgents/evil.plist")
        let entry = DeletionEntry(
            path: dest.path, bytes: 7, movedToTrash: true, dryRun: false,
            trashedPath: trashed.path, targetID: cacheTarget.id
        )

        let result = makeEngine().restore([entry])

        XCTAssertEqual(result.restoredCount, 0)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: dest.path), "Nothing may be planted outside the allowlist")
        XCTAssertTrue(fileManager.fileExists(atPath: trashed.path), "Refused restore must leave the Trash untouched")
    }

    func testRestoreRefusesEntryWithoutTargetMetadata() throws {
        let trashed = try stageTrashedFile(named: "orphan.bin")
        let dest = tempHome.appendingPathComponent("Library/Caches/orphan.bin")
        let entry = DeletionEntry(
            path: dest.path, bytes: 7, movedToTrash: true, dryRun: false,
            trashedPath: trashed.path
        )

        let result = makeEngine().restore([entry])

        XCTAssertEqual(result.restoredCount, 0)
        XCTAssertEqual(result.failures.first?.reason, "No cleanup target recorded for this entry")
        XCTAssertTrue(fileManager.fileExists(atPath: trashed.path))
    }

    func testRestoreRefusesSourceOutsideTrash() throws {
        // A "trashed" source that actually points at real user data outside the Trash.
        let outside = tempHome.appendingPathComponent("Documents-stand-in.bin")
        try Data("real data".utf8).write(to: outside)
        let dest = tempHome.appendingPathComponent("Library/Caches/whatever.bin")
        let entry = DeletionEntry(
            path: dest.path, bytes: 7, movedToTrash: true, dryRun: false,
            trashedPath: outside.path, targetID: cacheTarget.id
        )

        let result = makeEngine().restore([entry])

        XCTAssertEqual(result.restoredCount, 0)
        XCTAssertTrue(fileManager.fileExists(atPath: outside.path), "Source outside the Trash must not be moved")
    }

    func testPurgeRefusesPathOutsideTrash() throws {
        let outside = tempHome.appendingPathComponent("not-trash.bin")
        try Data("keep me".utf8).write(to: outside)
        let entry = DeletionEntry(
            path: outside.path, bytes: 7, movedToTrash: true, dryRun: false,
            trashedPath: outside.path, targetID: cacheTarget.id
        )

        XCTAssertEqual(makeEngine().purge([entry]), 0)
        XCTAssertTrue(fileManager.fileExists(atPath: outside.path))
    }

    func testDeletionEntriesRecordTheirTarget() async throws {
        let cacheRoot = tempHome.appendingPathComponent("Library/Caches")
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let item = cacheRoot.appendingPathComponent("stale.bin")
        try Data(repeating: 0xAB, count: 64).write(to: item)

        let resolved = ResolvedPath(path: item.path, displayName: "stale.bin", targetID: cacheTarget.id)
        let result = await makeEngine().delete(
            paths: [resolved],
            targets: [cacheTarget],
            options: CleanerOptions(cleanupLevel: .safe)
        )

        XCTAssertEqual(result.entries.first?.targetID, cacheTarget.id)
    }

    func testOlderLogLinesWithoutTargetIDStillDecode() throws {
        let legacyLine = """
        {"id":"6F9B26B4-3E36-4A1B-9F0A-111111111111","timestamp":700000000,"path":"/tmp/x","bytes":12,"movedToTrash":true,"dryRun":false}
        """
        let entry = try JSONDecoder().decode(DeletionEntry.self, from: Data(legacyLine.utf8))
        XCTAssertNil(entry.targetID)
    }

    func testRestoreRootsForDynamicTargetsAreStaticBases() {
        let validator = SafetyValidator(
            fileManager: fileManager,
            homeDirectory: tempHome,
            bootVolumeURL: tempHome,
            allowedTargets: CleanupTargetRegistry.all
        )
        let archives = CleanupTargetRegistry.level3.first { $0.id == "xcode-archives" }!
        XCTAssertEqual(
            validator.restoreRoots(for: archives),
            [tempHome.appendingPathComponent("Library/Developer/Xcode/Archives").path],
            "Dynamic targets restore into their fixed base directory, not re-resolved paths"
        )
        let docker = CleanupTargetRegistry.level2.first { $0.id == "docker-prune" }!
        XCTAssertTrue(validator.restoreRoots(for: docker).isEmpty, "Command targets have nothing to restore")
    }
}
