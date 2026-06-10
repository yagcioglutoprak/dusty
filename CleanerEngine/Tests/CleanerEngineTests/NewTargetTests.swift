import XCTest
@testable import CleanerEngine

/// Targets added in v1.5.0: Microsoft Teams (sandboxed container cache), Zoom update
/// installers, Telegram media caches (dynamic, per-account), and Ollama models (opt-in).
final class NewTargetTests: XCTestCase {
    var fileManager: FileManager!
    var tempHome: URL!

    override func setUpWithError() throws {
        fileManager = FileManager.default
        tempHome = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: tempHome)
    }

    private func target(_ id: String) -> CleanupTarget {
        CleanupTargetRegistry.all.first { $0.id == id }!
    }

    private func validator(for t: CleanupTarget) -> SafetyValidator {
        SafetyValidator(fileManager: fileManager, homeDirectory: tempHome, bootVolumeURL: tempHome, allowedTargets: [t])
    }

    private func home(_ relative: String) -> String {
        tempHome.appendingPathComponent(relative).path
    }

    private func makeDirs(_ relatives: [String]) throws {
        for relative in relatives {
            try fileManager.createDirectory(at: tempHome.appendingPathComponent(relative), withIntermediateDirectories: true)
        }
    }

    // MARK: - Microsoft Teams

    func testTeamsCacheIsSafeGatedAndContainerScoped() {
        let t = target("teams-cache")
        XCTAssertEqual(t.level, .safe)
        XCTAssertTrue(t.deletesContentsNotDirectory)
        XCTAssertTrue(t.regenerates)
        XCTAssertEqual(t.requiresAppBundleID, "com.microsoft.teams2")

        let v = validator(for: t)
        let cache = home("Library/Containers/com.microsoft.teams2/Data/Library/Caches")
        XCTAssertNil(v.validateDeletionPath(cache, for: t).error)
        XCTAssertNil(v.validateDeletionPath(cache + "/blob.bin", for: t).error)
        XCTAssertNotNil(v.validateDeletionPath(home("Library/Containers/com.microsoft.teams2/Data"), for: t).error,
                        "Only the container's Caches dir may validate, never the data root")
        XCTAssertNotNil(v.validateDeletionPath(home("Library/Containers"), for: t).error)
    }

    // MARK: - Zoom

    func testZoomUpdatesOnlyReachesTheAutoUpdaterFolder() {
        let t = target("zoom-updates")
        XCTAssertEqual(t.level, .safe)
        XCTAssertTrue(t.regenerates)

        let v = validator(for: t)
        let updater = home("Library/Application Support/zoom.us/AutoUpdater")
        XCTAssertNil(v.validateDeletionPath(updater, for: t).error)
        XCTAssertNil(v.validateDeletionPath(updater + "/Zoom.pkg", for: t).error)
        XCTAssertNotNil(v.validateDeletionPath(home("Library/Application Support/zoom.us"), for: t).error,
                        "zoom.us itself holds settings and meeting data, must be blocked")
        XCTAssertNotNil(v.validateDeletionPath(home("Library/Application Support/zoom.us/data"), for: t).error)
    }

    // MARK: - Telegram

    func testTelegramResolvesOnlyExistingMediaCaches() throws {
        let t = target("telegram-media-cache")
        XCTAssertTrue(t.usesDynamicPaths)
        XCTAssertEqual(t.level, .safe)

        try makeDirs([
            "Library/Application Support/Telegram Desktop/tdata/user_data/cache",
            "Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/account-12345/postbox/media",
            "Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/appstore/account-67890/postbox/media",
            // Decoys that must never resolve.
            "Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/account-12345/postbox/db",
            "Library/Application Support/Telegram Desktop/tdata/key_data"
        ])

        let v = validator(for: t)
        let resolved = Set(v.resolveAllowlistedPaths(for: t))
        XCTAssertEqual(resolved, [
            home("Library/Application Support/Telegram Desktop/tdata/user_data/cache"),
            home("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/account-12345/postbox/media"),
            home("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/appstore/account-67890/postbox/media"),
        ])
    }

    func testTelegramChatDatabaseAndSessionKeysNeverValidate() throws {
        let t = target("telegram-media-cache")
        try makeDirs([
            "Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/account-12345/postbox/media",
            "Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/account-12345/postbox/db",
            "Library/Application Support/Telegram Desktop/tdata/user_data/media_cache"
        ])
        let v = validator(for: t)
        let group = "Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram"

        XCTAssertNil(v.validateDeletionPath(home("\(group)/account-12345/postbox/media/file.mp4"), for: t).error)
        XCTAssertNotNil(v.validateDeletionPath(home("\(group)/account-12345/postbox/db"), for: t).error,
                        "Chat database must never validate")
        XCTAssertNotNil(v.validateDeletionPath(home(group), for: t).error,
                        "The whole group container must never validate")
        XCTAssertNotNil(v.validateDeletionPath(home("Library/Application Support/Telegram Desktop/tdata"), for: t).error,
                        "tdata holds session keys, must be blocked")
    }

    func testTelegramRestoreRootsCoverBothBuilds() {
        let t = target("telegram-media-cache")
        let v = validator(for: t)
        let roots = v.restoreRoots(for: t)
        XCTAssertTrue(roots.contains(home("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram")))
        XCTAssertTrue(roots.contains(home("Library/Application Support/Telegram Desktop/tdata/user_data/cache")))
    }

    // MARK: - Ollama

    func testOllamaModelsAreDeepAndStrictlyOptIn() {
        let t = target("ollama-models")
        XCTAssertEqual(t.level, .deep)
        XCTAssertTrue(t.requiresExplicitOptIn, "Models are deliberate downloads, never auto-selected")
        XCTAssertTrue(t.needsUserSelection)
        XCTAssertFalse(t.regenerates)

        let v = validator(for: t)
        XCTAssertNil(v.validateDeletionPath(home(".ollama/models"), for: t).error)
        XCTAssertNotNil(v.validateDeletionPath(home(".ollama"), for: t).error,
                        "~/.ollama also holds keys and history, must be blocked")
    }

    func testOllamaModelsScanIsNeverPreselected() async {
        let t = target("ollama-models")
        let dir = tempHome.appendingPathComponent(".ollama/models")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let engine = CleanerEngine(
            validator: SafetyValidator(fileManager: fileManager, homeDirectory: tempHome, bootVolumeURL: tempHome),
            homeDirectory: tempHome
        )
        // The validator expands "~" against tempHome, so the scan sees the temp models dir.
        let result = await engine.scanTarget(t, options: CleanerOptions())
        for path in result.resolvedPaths {
            XCTAssertFalse(path.isSelected, "Opt-in target must scan unselected")
        }
    }
}
