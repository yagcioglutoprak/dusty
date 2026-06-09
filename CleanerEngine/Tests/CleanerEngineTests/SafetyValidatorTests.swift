import XCTest
@testable import CleanerEngine

final class SafetyValidatorTests: XCTestCase {
    var tempHome: URL!
    var fileManager: FileManager!
    var validator: SafetyValidator!

    override func setUpWithError() throws {
        fileManager = FileManager.default
        tempHome = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempHome, withIntermediateDirectories: true)
        validator = SafetyValidator(fileManager: fileManager, homeDirectory: tempHome)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: tempHome)
    }

    func testAllowlistedUserCachePathIsPermitted() throws {
        let target = CleanupTargetRegistry.level1.first { $0.id == "user-caches" }!
        let cacheRoot = tempHome.appendingPathComponent("Library/Caches").path
        try fileManager.createDirectory(atPath: cacheRoot, withIntermediateDirectories: true)

        let child = (cacheRoot as NSString).appendingPathComponent("com.example.app")
        try fileManager.createDirectory(atPath: child, withIntermediateDirectories: true)

        let testValidator = SafetyValidator(
            fileManager: fileManager,
            homeDirectory: tempHome,
            allowedTargets: [target]
        )

        let expanded = testValidator.expandPath("~/Library/Caches")
        let testPath = (expanded as NSString).appendingPathComponent("com.example.app")

        let result = testValidator.validateDeletionPath(testPath, for: target)
        XCTAssertEqual(result.error, nil)
    }

    func testDocumentsPathIsProhibited() throws {
        let target = CleanupTargetRegistry.level1.first { $0.id == "user-caches" }!
        let docs = tempHome.appendingPathComponent("Documents/secret.txt").path
        try fileManager.createDirectory(at: tempHome.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        fileManager.createFile(atPath: docs, contents: Data())

        let result = validator.validateDeletionPath(docs, for: target)
        XCTAssertEqual(result.error, .prohibitedPath((docs as NSString).standardizingPath))
    }

    func testPathOutsideAllowlistIsRejected() throws {
        let target = CleanupTargetRegistry.level1.first { $0.id == "user-logs" }!
        let random = tempHome.appendingPathComponent("Library/Caches/evil").path
        try fileManager.createDirectory(atPath: random, withIntermediateDirectories: true)

        let testValidator = SafetyValidator(fileManager: fileManager, homeDirectory: tempHome, allowedTargets: [target])
        let result = testValidator.validateDeletionPath(random, for: target)
        XCTAssertEqual(result.error, .pathNotInAllowlist((random as NSString).standardizingPath))
    }

    func testSymlinkRefusal() throws {
        let target = CleanupTargetRegistry.level1.first { $0.id == "user-caches" }!
        let cacheRoot = tempHome.appendingPathComponent("Library/Caches")
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)

        let realTarget = tempHome.appendingPathComponent("Documents")
        try fileManager.createDirectory(at: realTarget, withIntermediateDirectories: true)

        let symlink = cacheRoot.appendingPathComponent("link-to-docs")
        try fileManager.createSymbolicLink(at: symlink, withDestinationURL: realTarget)

        let testValidator = SafetyValidator(fileManager: fileManager, homeDirectory: tempHome, allowedTargets: [target])
        let result = testValidator.validateDeletionPath(symlink.path, for: target)
        XCTAssertEqual(result.error, .symlinkRefusal((symlink.path as NSString).standardizingPath))
    }

    func testBootVolumeCheck() throws {
        // Path on temp "boot" volume should pass volume check when under allowlist
        let cache = tempHome.appendingPathComponent("Library/Caches/item").path
        try fileManager.createDirectory(atPath: cache, withIntermediateDirectories: true)

        let testValidator = SafetyValidator(
            fileManager: fileManager,
            homeDirectory: tempHome,
            bootVolumeURL: tempHome,
            allowedTargets: CleanupTargetRegistry.level1
        )
        XCTAssertTrue(testValidator.isOnBootVolume(URL(fileURLWithPath: cache)))
    }

    func testOutsideBootVolumeRejected() throws {
        let target = CleanupTargetRegistry.level1.first { $0.id == "user-caches" }!
        let cacheRoot = tempHome.appendingPathComponent("Library/Caches").path
        try fileManager.createDirectory(atPath: cacheRoot, withIntermediateDirectories: true)

        // Non-existent volume path forces prefix fallback where cache is not under boot root
        let fakeBoot = URL(fileURLWithPath: "/Volumes/DustyTestVolume")
        let testValidator = SafetyValidator(
            fileManager: fileManager,
            homeDirectory: tempHome,
            bootVolumeURL: fakeBoot,
            allowedTargets: [target]
        )

        let child = (cacheRoot as NSString).appendingPathComponent("app")
        try fileManager.createDirectory(atPath: child, withIntermediateDirectories: true)

        let result = testValidator.validateDeletionPath(child, for: target)
        XCTAssertEqual(result.error, .outsideBootVolume((child as NSString).standardizingPath))
    }

    func testExpandPathUsesHomeDirectory() {
        let expanded = validator.expandPath("~/Library/Logs")
        XCTAssertTrue(expanded.hasSuffix("/Library/Logs"))
        XCTAssertTrue(expanded.hasPrefix(tempHome.path))
    }

    func testRegistryContainsAllLevels() {
        XCTAssertFalse(CleanupTargetRegistry.level1.isEmpty)
        XCTAssertFalse(CleanupTargetRegistry.level2.isEmpty)
        XCTAssertFalse(CleanupTargetRegistry.level3.isEmpty)
        for target in CleanupTargetRegistry.all {
            XCTAssertFalse(target.id.isEmpty)
            XCTAssertFalse(target.displayName.isEmpty)
        }
    }
}

extension Result where Success == Void, Failure == SafetyError {
    var error: SafetyError? {
        if case .failure(let e) = self { return e }
        return nil
    }
}
