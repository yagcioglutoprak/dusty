import XCTest
@testable import CleanerEngine

final class DeletionBehaviorTests: XCTestCase {
    var tempHome: URL!
    var fileManager: FileManager!
    var engine: CleanerEngine!
    var logStore: InMemoryDeletionLogStore!

    override func setUpWithError() throws {
        fileManager = FileManager.default
        tempHome = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempHome, withIntermediateDirectories: true)
        logStore = InMemoryDeletionLogStore()

        let cacheTarget = CleanupTarget(
            id: "test-cache",
            displayName: "Test Cache",
            level: .safe,
            pathTemplates: ["~/Library/Caches"],
            category: "Test",
            deletesContentsNotDirectory: true,
            regenerates: true
        )

        let validator = SafetyValidator(
            fileManager: fileManager,
            homeDirectory: tempHome,
            bootVolumeURL: tempHome,
            allowedTargets: [cacheTarget]
        )

        engine = CleanerEngine(
            fileManager: fileManager,
            validator: validator,
            sizeCalculator: SizeCalculator(fileManager: fileManager),
            diskMonitor: DiskSpaceMonitor(fileManager: fileManager),
            deletionLog: logStore
        )
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: tempHome)
    }

    func testDeletesContentsNotDirectoryLeavesParent() async throws {
        let cacheRoot = tempHome.appendingPathComponent("Library/Caches")
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        let child = cacheRoot.appendingPathComponent("com.test.app")
        try fileManager.createDirectory(at: child, withIntermediateDirectories: true)
        let file = child.appendingPathComponent("cache.db")
        try Data(repeating: 0xAB, count: 1024).write(to: file)

        let target = CleanupTarget(
            id: "test-cache",
            displayName: "Test Cache",
            level: .safe,
            pathTemplates: ["~/Library/Caches"],
            category: "Test",
            deletesContentsNotDirectory: true,
            regenerates: true
        )

        let resolved = ResolvedPath(
            path: child.path,
            displayName: child.path,
            targetID: target.id,
            estimatedBytes: 1024,
            isSelected: true
        )

        let result = await engine.delete(paths: [resolved], targets: [target], options: CleanerOptions(dryRun: false))

        XCTAssertTrue(fileManager.fileExists(atPath: cacheRoot.path))
        XCTAssertFalse(fileManager.fileExists(atPath: child.path))
        XCTAssertGreaterThan(result.bytesFreed, 0)
    }

    func testDryRunDoesNotDelete() async throws {
        let cacheRoot = tempHome.appendingPathComponent("Library/Caches/item")
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let file = cacheRoot.appendingPathComponent("data.bin")
        try Data(count: 512).write(to: file)

        let target = CleanupTarget(
            id: "test-cache",
            displayName: "Test Cache",
            level: .safe,
            pathTemplates: ["~/Library/Caches"],
            category: "Test",
            deletesContentsNotDirectory: false,
            regenerates: true
        )

        let resolved = ResolvedPath(path: cacheRoot.path, displayName: cacheRoot.path, targetID: target.id, isSelected: true)
        _ = await engine.delete(paths: [resolved], targets: [target], options: CleanerOptions(dryRun: true))

        XCTAssertTrue(fileManager.fileExists(atPath: file.path))
        XCTAssertEqual(logStore.entries.count, 1)
        XCTAssertTrue(logStore.entries[0].dryRun)
    }

    func testSymlinkIsNotFollowedForDeletion() async throws {
        let cacheRoot = tempHome.appendingPathComponent("Library/Caches")
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        let secret = tempHome.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: secret)

        let link = cacheRoot.appendingPathComponent("evil-link")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: secret)

        let target = CleanupTarget(
            id: "test-cache",
            displayName: "Test Cache",
            level: .safe,
            pathTemplates: ["~/Library/Caches"],
            category: "Test",
            deletesContentsNotDirectory: false,
            regenerates: true
        )

        let resolved = ResolvedPath(path: link.path, displayName: link.path, targetID: target.id, isSelected: true)
        let result = await engine.delete(paths: [resolved], targets: [target], options: CleanerOptions(dryRun: false))

        XCTAssertTrue(fileManager.fileExists(atPath: secret.path), "Symlink target must not be deleted")
        XCTAssertFalse(result.skippedPaths.isEmpty, "Symlink path should be skipped")
        XCTAssertTrue(result.entries.isEmpty, "No deletion entry should be recorded for symlinks")
    }

    func testDeleteReusesScanEstimateInsteadOfRemeasuring() async throws {
        // The scan's measurement rides along in ResolvedPath.estimatedBytes; the
        // delete must use it rather than re-walking the item (re-walking would
        // dominate the clean time for trash-move deletes). A deliberate mismatch
        // between estimate and on-disk size proves which one was used.
        let cacheRoot = tempHome.appendingPathComponent("Library/Caches")
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let item = cacheRoot.appendingPathComponent("small.bin")
        try Data(count: 100).write(to: item)

        let target = CleanupTarget(
            id: "test-cache",
            displayName: "Test Cache",
            level: .safe,
            pathTemplates: ["~/Library/Caches"],
            category: "Test",
            deletesContentsNotDirectory: true,
            regenerates: true
        )

        let resolved = ResolvedPath(path: item.path, displayName: "small.bin", targetID: target.id, estimatedBytes: 5000, isSelected: true)
        let result = await engine.delete(paths: [resolved], targets: [target], options: CleanerOptions(dryRun: false))

        XCTAssertFalse(fileManager.fileExists(atPath: item.path))
        XCTAssertEqual(result.entries.first?.bytes, 5000, "Delete must reuse the scan's estimate")
        XCTAssertEqual(result.bytesFreed, 5000)
    }

    func testDeleteMeasuresWhenNoEstimateProvided() async throws {
        let cacheRoot = tempHome.appendingPathComponent("Library/Caches")
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let item = cacheRoot.appendingPathComponent("unmeasured.bin")
        try Data(count: 4096).write(to: item)

        let target = CleanupTarget(
            id: "test-cache",
            displayName: "Test Cache",
            level: .safe,
            pathTemplates: ["~/Library/Caches"],
            category: "Test",
            deletesContentsNotDirectory: true,
            regenerates: true
        )

        let resolved = ResolvedPath(path: item.path, displayName: "unmeasured.bin", targetID: target.id, isSelected: true)
        let result = await engine.delete(paths: [resolved], targets: [target], options: CleanerOptions(dryRun: false))

        XCTAssertFalse(fileManager.fileExists(atPath: item.path))
        XCTAssertGreaterThan(result.entries.first?.bytes ?? 0, 0, "Without an estimate the delete must measure the item itself")
    }

    func testOneFailingChildDoesNotAbortRemainingChildren() async throws {
        let cacheRoot = tempHome.appendingPathComponent("Library/Caches")
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        // A read-only directory whose contents cannot be unlinked.
        let locked = cacheRoot.appendingPathComponent("a-locked")
        try fileManager.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(count: 8).write(to: locked.appendingPathComponent("pin.bin"))
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let junk = cacheRoot.appendingPathComponent("b-junk")
        try fileManager.createDirectory(at: junk, withIntermediateDirectories: true)
        try Data(count: 8).write(to: junk.appendingPathComponent("old.bin"))

        let target = CleanupTarget(
            id: "test-cache",
            displayName: "Test Cache",
            level: .safe,
            pathTemplates: ["~/Library/Caches"],
            category: "Test",
            deletesContentsNotDirectory: true,
            regenerates: true
        )

        // Passing the allowlist root itself exercises the directory-contents path.
        let resolved = ResolvedPath(path: cacheRoot.path, displayName: "Caches", targetID: target.id, isSelected: true)
        let result = await engine.delete(paths: [resolved], targets: [target], options: CleanerOptions(dryRun: false))

        XCTAssertFalse(fileManager.fileExists(atPath: junk.path), "Children after a failing one must still be deleted")
        XCTAssertTrue(fileManager.fileExists(atPath: locked.path), "The undeletable child stays put")
        XCTAssertFalse(result.skippedPaths.isEmpty, "The failure must still be reported, not swallowed")
    }
}

// MARK: - Test doubles

final class InMemoryDeletionLogStore: DeletionLogStore, @unchecked Sendable {
    var entries: [DeletionEntry] = []
    let logFileURL = URL(fileURLWithPath: "/tmp/dusty-test-log.jsonl")

    func append(_ entry: DeletionEntry) throws {
        entries.append(entry)
    }

    func loadAll() throws -> [DeletionEntry] {
        entries
    }
}
