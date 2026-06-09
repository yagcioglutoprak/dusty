import XCTest
@testable import CleanerEngine

/// Regression tests for the safety + correctness hardening:
/// - "Empty Trash" must permanently delete even under Safe-undo (never trash-shuffle).
/// - Ancestor symlinks must not let a delete escape its allowlist root.
/// - Xcode archives enumerate as individual .xcarchive bundles.
/// - Docker size parsing handles the unit variants Docker emits.
final class EngineHardeningTests: XCTestCase {
    var tempHome: URL!
    var fileManager: FileManager!
    var logStore: InMemoryDeletionLogStore!

    override func setUpWithError() throws {
        fileManager = FileManager.default
        tempHome = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempHome, withIntermediateDirectories: true)
        logStore = InMemoryDeletionLogStore()
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: tempHome)
    }

    private func makeEngine(allowing targets: [CleanupTarget]) -> CleanerEngine {
        let validator = SafetyValidator(
            fileManager: fileManager,
            homeDirectory: tempHome,
            bootVolumeURL: tempHome,
            allowedTargets: targets
        )
        return CleanerEngine(
            fileManager: fileManager,
            validator: validator,
            sizeCalculator: SizeCalculator(fileManager: fileManager),
            diskMonitor: DiskSpaceMonitor(fileManager: fileManager),
            deletionLog: logStore
        )
    }

    // MARK: - P0: Empty Trash always permanent

    func testBypassesTrashForcesPermanentDeleteEvenUnderSafeUndo() async throws {
        // Under Safe-undo, effectiveMoveToTrash is true...
        let options = CleanerOptions(cleanupLevel: .safe, trashForUndo: true)
        XCTAssertTrue(options.effectiveMoveToTrash, "Precondition: Safe-undo would otherwise move to Trash")

        let trashTarget = CleanupTarget(
            id: "test-trash",
            displayName: "Test Trash",
            level: .safe,
            pathTemplates: ["~/Library/Caches"],
            category: "Test",
            deletesContentsNotDirectory: true,
            regenerates: true,
            bypassesTrash: true
        )

        let cacheRoot = tempHome.appendingPathComponent("Library/Caches")
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let item = cacheRoot.appendingPathComponent("junk.bin")
        try Data(repeating: 0xCD, count: 2048).write(to: item)

        let resolved = ResolvedPath(path: item.path, displayName: "junk.bin", targetID: trashTarget.id, estimatedBytes: 2048, isSelected: true)
        let engine = makeEngine(allowing: [trashTarget])
        let result = await engine.delete(paths: [resolved], targets: [trashTarget], options: options)

        XCTAssertFalse(fileManager.fileExists(atPath: item.path), "Item must be permanently deleted")
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertFalse(result.entries[0].movedToTrash, "bypassesTrash must override effectiveMoveToTrash")
        XCTAssertNil(result.entries[0].trashedPath, "Permanent delete must not record a trashed path")
        XCTAssertGreaterThan(result.bytesFreed, 0)
    }

    // MARK: - P1: Ancestor symlink escape

    func testAncestorSymlinkCannotEscapeAllowlist() throws {
        let target = CleanupTargetRegistry.level1.first { $0.id == "user-caches" }!
        let validator = SafetyValidator(fileManager: fileManager, homeDirectory: tempHome, bootVolumeURL: tempHome, allowedTargets: [target])

        let cacheRoot = tempHome.appendingPathComponent("Library/Caches")
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        // Real user data OUTSIDE the allowlist, with a non-symlink leaf inside it.
        let secret = tempHome.appendingPathComponent("secret-data")
        try fileManager.createDirectory(at: secret, withIntermediateDirectories: true)
        let secretFile = secret.appendingPathComponent("passwords.txt")
        try Data("hunter2".utf8).write(to: secretFile)

        // A symlinked ANCESTOR directory inside the cache that points at the secret dir.
        let relocated = cacheRoot.appendingPathComponent("relocated")
        try fileManager.createSymbolicLink(at: relocated, withDestinationURL: secret)

        // The leaf itself is a regular file; only an ancestor is a symlink.
        let candidate = relocated.appendingPathComponent("passwords.txt").path
        let result = validator.validateDeletionPath(candidate, for: target)

        if case .success = result {
            XCTFail("Ancestor symlink must not pass validation (would delete real user data)")
        }
        XCTAssertTrue(fileManager.fileExists(atPath: secretFile.path), "Secret file must be untouched")
    }

    func testNormalNestedCachePathStillValidates() throws {
        let target = CleanupTargetRegistry.level1.first { $0.id == "user-caches" }!
        let validator = SafetyValidator(fileManager: fileManager, homeDirectory: tempHome, bootVolumeURL: tempHome, allowedTargets: [target])

        let nested = tempHome.appendingPathComponent("Library/Caches/com.app/Sub/file.bin")
        try fileManager.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 16).write(to: nested)

        let result = validator.validateDeletionPath(nested.path, for: target)
        XCTAssertNil(result.error, "A plain nested cache path with no symlinks must still validate")
    }

    // MARK: - xcode-archives per-archive enumeration

    func testArchivesEnumerateIndividually() throws {
        let target = CleanupTargetRegistry.level3.first { $0.id == "xcode-archives" }!
        let validator = SafetyValidator(fileManager: fileManager, homeDirectory: tempHome, bootVolumeURL: tempHome, allowedTargets: [target])

        let archivesBase = tempHome.appendingPathComponent("Library/Developer/Xcode/Archives/2026-01-15")
        try fileManager.createDirectory(at: archivesBase, withIntermediateDirectories: true)
        let a1 = archivesBase.appendingPathComponent("MyApp 1.0.xcarchive")
        let a2 = archivesBase.appendingPathComponent("MyApp 1.1.xcarchive")
        try fileManager.createDirectory(at: a1, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: a2, withIntermediateDirectories: true)
        // A stray non-archive file must be ignored.
        try Data().write(to: archivesBase.appendingPathComponent("notes.txt"))

        let resolved = Set(validator.resolveAllowlistedPaths(for: target))
        XCTAssertTrue(resolved.contains(a1.path))
        XCTAssertTrue(resolved.contains(a2.path))
        XCTAssertEqual(resolved.count, 2, "Only .xcarchive bundles should be enumerated")
    }

    // MARK: - Docker size parsing

    func testParseDockerSizeVariants() {
        let engine = makeEngine(allowing: CleanupTargetRegistry.all)
        let cases: [(String, Int64?)] = [
            ("0B", 0),
            ("0", 0),
            ("1.2GB", Int64(1.2 * 1_073_741_824)),
            ("12.5MB", Int64(12.5 * 1_048_576)),
            ("512KB", 512 * 1024),
            ("512kB", 512 * 1024),
            ("256B", 256),
            ("  3GB ", Int64(3 * 1_073_741_824)),
            ("garbage", nil),
            ("", nil),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(engine.parseDockerSizeForTesting(input), expected, "parseDockerSize(\(input))")
        }
    }
}
