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
