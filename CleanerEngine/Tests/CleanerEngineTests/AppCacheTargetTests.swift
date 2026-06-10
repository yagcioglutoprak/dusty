import XCTest
@testable import CleanerEngine

/// New Safe targets for app caches that live under Application Support, which the
/// blanket `~/Library/Caches` sweep does not reach. The safety requirement: only the
/// specific cache subfolder is reachable, never the app's whole Application Support
/// folder (which holds real data like workspaces and settings).
final class AppCacheTargetTests: XCTestCase {
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

    private func appSupport(_ relative: String) -> String {
        tempHome.appendingPathComponent("Library/Application Support/\(relative)").path
    }

    private let appCacheIDs = [
        "discord-cache", "spotify-cache", "vscode-cache", "slack-cache",
        "cursor-cache", "signal-cache", "obsidian-cache",
    ]

    func testAppCacheTargetsAreSafeRegeneratingAndAppClosedGated() {
        for id in appCacheIDs {
            let t = target(id)
            XCTAssertEqual(t.level, .safe, "\(id) must be a Safe target")
            XCTAssertTrue(t.deletesContentsNotDirectory, "\(id) clears cache contents, keeps the dir")
            XCTAssertTrue(t.regenerates, "\(id) regenerates")
            XCTAssertNotNil(t.requiresAppClosed, "\(id) must be gated on the app being closed")
            XCTAssertNotNil(t.requiresAppBundleID, "\(id) must carry a bundle id for running-app detection")
            XCTAssertFalse(t.pathTemplates.isEmpty, "\(id) must declare cache subpaths")
        }
    }

    func testEveryCacheSubpathValidatesAndStaysUnderApplicationSupport() throws {
        for id in appCacheIDs {
            let t = target(id)
            let v = validator(for: t)
            for template in t.pathTemplates {
                let path = v.expandPath(template)
                XCTAssertTrue(path.contains("/Library/Application Support/"), "\(id) subpath should be under Application Support")
                XCTAssertNil(v.validateDeletionPath(path, for: t).error, "Cache root \(path) must validate")
                // A child inside the cache dir must also validate (this is what delete walks).
                let child = (path as NSString).appendingPathComponent("blob.bin")
                XCTAssertNil(v.validateDeletionPath(child, for: t).error, "Cache child \(child) must validate")
            }
        }
    }

    func testAppOwnFolderAndNonCacheSiblingsAreBlocked() throws {
        // Discord: the whole app folder and a real-data sibling must never validate.
        let discord = target("discord-cache")
        let v = validator(for: discord)
        XCTAssertNotNil(v.validateDeletionPath(appSupport("discord"), for: discord).error,
                        "The app's whole Application Support folder must be blocked")
        XCTAssertNotNil(v.validateDeletionPath(appSupport("discord/Local Storage"), for: discord).error,
                        "A non-cache sibling holding real data must be blocked")
        XCTAssertNotNil(v.validateDeletionPath(appSupport(""), for: discord).error,
                        "Application Support itself must be blocked")
    }

    func testAppCacheTargetsLiveInTheSafeLevelRegistry() {
        let safeIDs = Set(CleanupTargetRegistry.level1.map(\.id))
        for id in appCacheIDs {
            XCTAssertTrue(safeIDs.contains(id), "\(id) must be registered in level1 (Safe)")
        }
    }

    // MARK: - Derived Application Support exemptions

    func testApplicationSupportExemptionsAreDerivedFromTargetTemplates() throws {
        // A brand-new target under Application Support must validate with NO validator
        // edit: the exemption list is derived from the target's own path templates.
        let newApp = CleanupTarget(
            id: "test-newapp-cache",
            displayName: "NewApp Cache",
            level: .safe,
            pathTemplates: ["~/Library/Application Support/NewApp/Cache"],
            category: "App Cache",
            deletesContentsNotDirectory: true,
            regenerates: true
        )
        let v = validator(for: newApp)
        let cache = appSupport("NewApp/Cache")
        XCTAssertNil(v.validateDeletionPath(cache, for: newApp).error,
                     "A registered App Support cache template must be exempt automatically")
        XCTAssertNil(v.validateDeletionPath(cache + "/blob.bin", for: newApp).error,
                     "Children of the derived cache dir must validate too")
        XCTAssertNotNil(v.validateDeletionPath(appSupport("NewApp"), for: newApp).error,
                        "The app's whole folder must stay prohibited")
        XCTAssertNotNil(v.validateDeletionPath(appSupport("NewApp/Local Storage"), for: newApp).error,
                        "Non-cache siblings must stay prohibited")
    }

    func testValidatorWithoutAppSupportTargetsBlocksAllOfApplicationSupport() throws {
        // A validator allowing only a non-App-Support target derives no exemptions,
        // so even a known cache-shaped path under Application Support is prohibited.
        let target = CleanupTargetRegistry.all.first { $0.id == "user-caches" }!
        let v = validator(for: target)
        XCTAssertNotNil(v.validateDeletionPath(appSupport("discord/Cache"), for: target).error,
                        "No exemption may leak in from targets the validator does not allow")
    }

    // MARK: - XDG cache target

    func testXDGCacheTargetBasics() {
        let t = target("xdg-cache")
        XCTAssertEqual(t.level, .developer)
        XCTAssertTrue(t.deletesContentsNotDirectory, "Clears contents, keeps ~/.cache itself")
        XCTAssertTrue(t.regenerates)
        XCTAssertEqual(t.pathTemplates, ["~/.cache"])
        XCTAssertTrue(CleanupTargetRegistry.level2.contains { $0.id == "xdg-cache" })
    }

    func testXDGCacheChildValidatesAndHomeRootDoesNot() throws {
        let t = target("xdg-cache")
        let v = validator(for: t)
        let child = tempHome.appendingPathComponent(".cache/huggingface").path
        XCTAssertNil(v.validateDeletionPath(child, for: t).error, "Children of ~/.cache must validate")
        XCTAssertNotNil(v.validateDeletionPath(tempHome.path, for: t).error, "Home itself must never validate")
        XCTAssertNotNil(v.validateDeletionPath(tempHome.appendingPathComponent("Documents").path, for: t).error,
                        "Prohibited prefixes stay blocked")
    }
}
