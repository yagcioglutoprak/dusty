import XCTest
@testable import CleanerEngine

/// Targets added for issues #1 and #2: uv, Bun, and Deno download caches, plus the
/// Maven local repository. The Maven case is the interesting one: `mvn install` puts
/// locally built artifacts in `~/.m2/repository` that no remote can re-supply, so the
/// target must be opt-in and must not claim to regenerate.
final class PackageManagerTargetTests: XCTestCase {
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

    func testDownloadCachesAreDeveloperLevelAndRegenerate() {
        for id in ["uv-cache", "bun-cache", "deno-cache", "dart-pub-cache"] {
            let t = target(id)
            XCTAssertEqual(t.level, .developer, "\(id) belongs in the Developer level")
            XCTAssertTrue(t.regenerates, "\(id) is a pure download cache")
            XCTAssertTrue(t.deletesContentsNotDirectory, "\(id) clears contents, keeps the dir")
            XCTAssertFalse(t.requiresExplicitOptIn, "\(id) needs no opt-in: it re-downloads on demand")
        }
    }

    func testMavenRepositoryIsOptInAndDoesNotClaimToRegenerate() {
        let maven = target("maven-repository")
        XCTAssertTrue(maven.requiresExplicitOptIn, "Locally installed artifacts cannot be re-downloaded")
        XCTAssertFalse(maven.regenerates)
        XCTAssertTrue(maven.needsUserSelection, "Opt-in targets must never be pre-selected")
    }

    func testCachePathsValidateAndForeignSiblingsDoNot() throws {
        for (id, sibling) in [
            ("uv-cache", "~/Library/Caches"),
            ("bun-cache", "~/.bun"),
            ("deno-cache", "~/Library/Caches"),
            ("maven-repository", "~/.m2"),
            // The directory above ~/.pub-cache is the home folder itself,
            // which must never validate.
            ("dart-pub-cache", "~"),
        ] {
            let t = target(id)
            let v = validator(for: t)
            for template in t.pathTemplates {
                let root = v.expandPath(template)
                XCTAssertNil(v.validateDeletionPath(root, for: t).error, "\(id) root must validate")
                let child = (root as NSString).appendingPathComponent("some-item")
                XCTAssertNil(v.validateDeletionPath(child, for: t).error, "\(id) child must validate")
            }
            // The parent directory above the cache must never validate: ~/.bun also
            // holds the bun binary, ~/.m2 holds settings.xml, and so on.
            let parent = v.expandPath(sibling)
            XCTAssertNotNil(v.validateDeletionPath(parent, for: t).error, "\(id) must not reach \(sibling)")
        }
    }
}
