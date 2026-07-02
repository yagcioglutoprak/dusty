import XCTest
@testable import CleanerEngine

/// Firefox and Edge cache targets (issues #8 and #9). Firefox keeps its per-profile
/// disk cache under ~/Library/Caches/Firefox/Profiles; Edge is Chromium, so its
/// layout mirrors the Chrome target. Both must be gated on the app being closed and
/// must never reach outside their cache roots.
final class BrowserCacheTargetTests: XCTestCase {
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

    func testBrowserCacheTargetsAreSafeRegeneratingAndAppClosedGated() {
        for id in ["firefox-cache", "edge-cache"] {
            let t = target(id)
            XCTAssertEqual(t.level, .safe, "\(id) must be a Safe target")
            XCTAssertEqual(t.category, "Browser")
            XCTAssertTrue(t.deletesContentsNotDirectory, "\(id) clears cache contents, keeps the dir")
            XCTAssertTrue(t.regenerates, "\(id) regenerates")
            XCTAssertNotNil(t.requiresAppClosed, "\(id) must be gated on the app being closed")
            XCTAssertNotNil(t.requiresAppBundleID, "\(id) must carry a bundle id for running-app detection")
            XCTAssertTrue(CleanupTargetRegistry.level1.contains { $0.id == id }, "\(id) must be registered in level1")
        }
    }

    func testCacheRootsAndChildrenValidate() throws {
        for id in ["firefox-cache", "edge-cache"] {
            let t = target(id)
            let v = validator(for: t)
            for template in t.pathTemplates {
                let root = v.expandPath(template)
                XCTAssertNil(v.validateDeletionPath(root, for: t).error, "\(id) root \(root) must validate")
                let child = (root as NSString).appendingPathComponent("profile.default/cache2")
                XCTAssertNil(v.validateDeletionPath(child, for: t).error, "\(id) child \(child) must validate")
            }
        }
    }

    func testNothingOutsideTheCacheRootsValidates() throws {
        // Firefox: the Caches root above the target and the profile data folder
        // under Application Support (bookmarks, passwords) must never validate.
        let firefox = target("firefox-cache")
        let fv = validator(for: firefox)
        XCTAssertNotNil(fv.validateDeletionPath(tempHome.appendingPathComponent("Library/Caches").path, for: firefox).error,
                        "~/Library/Caches itself must not validate for the Firefox target")
        XCTAssertNotNil(fv.validateDeletionPath(tempHome.appendingPathComponent("Library/Application Support/Firefox/Profiles").path, for: firefox).error,
                        "Firefox profile data (bookmarks, passwords) must never validate")

        // Edge: the whole Application Support folder holds real profile data.
        let edge = target("edge-cache")
        let ev = validator(for: edge)
        XCTAssertNotNil(ev.validateDeletionPath(tempHome.appendingPathComponent("Library/Application Support/Microsoft Edge").path, for: edge).error,
                        "Edge's whole Application Support folder must be blocked")
        XCTAssertNotNil(ev.validateDeletionPath(tempHome.appendingPathComponent("Library/Application Support/Microsoft Edge/Default").path, for: edge).error,
                        "The Edge profile folder must be blocked; only the Service Worker cache inside it is allowed")
    }
}
