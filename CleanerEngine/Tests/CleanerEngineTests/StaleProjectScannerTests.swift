import XCTest
@testable import CleanerEngine

/// The stale project finder must only ever offer tool-owned artifact directories
/// (marker file next to them), only in projects nothing has touched for the
/// threshold, and never through a symlink. Everything it offers is manual-pick.
final class StaleProjectScannerTests: XCTestCase {
    var fileManager: FileManager!
    var tempHome: URL!
    var projectsRoot: URL!

    private let day: TimeInterval = 86400
    private let now = Date()

    override func setUpWithError() throws {
        fileManager = FileManager.default
        tempHome = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        projectsRoot = tempHome.appendingPathComponent("Developer")
        try fileManager.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: tempHome)
    }

    /// A project with a marker, an artifact dir, and every mtime pushed `ageDays` back.
    @discardableResult
    private func makeProject(
        _ name: String,
        marker: String = "package.json",
        artifact: String = "node_modules",
        ageDays: Int
    ) throws -> URL {
        let project = projectsRoot.appendingPathComponent(name)
        let artifactDir = project.appendingPathComponent(artifact)
        try fileManager.createDirectory(at: artifactDir, withIntermediateDirectories: true)
        fileManager.createFile(atPath: project.appendingPathComponent(marker).path, contents: Data("{}".utf8))
        fileManager.createFile(atPath: artifactDir.appendingPathComponent("blob.bin").path, contents: Data(count: 128))
        let stamp = now.addingTimeInterval(-Double(ageDays) * day)
        for path in [project.appendingPathComponent(marker).path, artifactDir.path, project.path] {
            try fileManager.setAttributes([.modificationDate: stamp], ofItemAtPath: path)
        }
        return artifactDir
    }

    private func scan(thresholdDays: Int = 30) -> [StaleProjectArtifact] {
        StaleProjectScanner.staleArtifacts(
            scanRoots: [projectsRoot.path],
            fileManager: fileManager,
            now: now,
            thresholdDays: thresholdDays
        )
    }

    func testFindsNodeModulesInAnUntouchedProject() throws {
        let artifact = try makeProject("old-app", ageDays: 90)
        let found = scan()
        XCTAssertEqual(found.map(\.path), [artifact.path])
        XCTAssertEqual(found.first?.projectName, "old-app")
        XCTAssertEqual(found.first?.artifactName, "node_modules")
    }

    func testActiveProjectIsLeftAlone() throws {
        try makeProject("busy-app", ageDays: 2)
        XCTAssertTrue(scan().isEmpty)
    }

    func testRecentCommitCountsAsActivityEvenWhenSourcesLookOld() throws {
        let artifact = try makeProject("committed-app", ageDays: 90)
        let project = artifact.deletingLastPathComponent()
        let git = project.appendingPathComponent(".git")
        try fileManager.createDirectory(at: git, withIntermediateDirectories: true)
        fileManager.createFile(atPath: git.appendingPathComponent("index").path, contents: Data())
        try fileManager.setAttributes([.modificationDate: now.addingTimeInterval(-day)],
                                      ofItemAtPath: git.appendingPathComponent("index").path)
        try fileManager.setAttributes([.modificationDate: now.addingTimeInterval(-90 * day)],
                                      ofItemAtPath: project.path)
        XCTAssertTrue(scan().isEmpty, "A fresh .git/index means someone is working here")
    }

    func testArtifactChurnAloneDoesNotCountAsActivity() throws {
        // The artifact dir was touched yesterday (package manager, indexer), but
        // no project file was: still stale.
        let artifact = try makeProject("indexer-victim", ageDays: 90)
        try fileManager.setAttributes([.modificationDate: now.addingTimeInterval(-day)],
                                      ofItemAtPath: artifact.path)
        XCTAssertEqual(scan().map(\.path), [artifact.path])
    }

    func testDirectoryNamedTargetWithoutCargoTomlIsNeverOffered() throws {
        // A folder someone named "target" holding real files, no Cargo.toml.
        let project = projectsRoot.appendingPathComponent("photos")
        let decoy = project.appendingPathComponent("target")
        try fileManager.createDirectory(at: decoy, withIntermediateDirectories: true)
        fileManager.createFile(atPath: decoy.appendingPathComponent("real-data.jpg").path, contents: Data(count: 64))
        let stamp = now.addingTimeInterval(-200 * day)
        for path in [decoy.path, project.path] {
            try fileManager.setAttributes([.modificationDate: stamp], ofItemAtPath: path)
        }
        XCTAssertTrue(scan().isEmpty, "No manifest next to it, not an artifact")
    }

    func testSymlinkedArtifactIsNeverOffered() throws {
        let project = projectsRoot.appendingPathComponent("linked-app")
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        fileManager.createFile(atPath: project.appendingPathComponent("package.json").path, contents: Data("{}".utf8))
        let realTarget = tempHome.appendingPathComponent("precious-data")
        try fileManager.createDirectory(at: realTarget, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            at: project.appendingPathComponent("node_modules"),
            withDestinationURL: realTarget
        )
        let stamp = now.addingTimeInterval(-200 * day)
        try fileManager.setAttributes([.modificationDate: stamp], ofItemAtPath: project.path)
        try fileManager.setAttributes([.modificationDate: stamp],
                                      ofItemAtPath: project.appendingPathComponent("package.json").path)
        XCTAssertTrue(scan().isEmpty, "A symlinked artifact could point anywhere")
    }

    func testProjectsNestedBelowGroupFoldersAreFound() throws {
        let group = projectsRoot.appendingPathComponent("clients/acme")
        try fileManager.createDirectory(at: group, withIntermediateDirectories: true)
        let project = group.appendingPathComponent("site")
        let artifact = project.appendingPathComponent("node_modules")
        try fileManager.createDirectory(at: artifact, withIntermediateDirectories: true)
        fileManager.createFile(atPath: project.appendingPathComponent("package.json").path, contents: Data("{}".utf8))
        let stamp = now.addingTimeInterval(-90 * day)
        for path in [project.path, project.appendingPathComponent("package.json").path, artifact.path] {
            try fileManager.setAttributes([.modificationDate: stamp], ofItemAtPath: path)
        }
        XCTAssertEqual(scan().map(\.path), [artifact.path])
    }

    // MARK: - Registry and validation wiring

    private var target: CleanupTarget {
        CleanupTargetRegistry.level3.first { $0.id == "stale-project-artifacts" }!
    }

    func testTargetIsDeepDynamicAndManualPickOnly() {
        XCTAssertEqual(target.level, .deep)
        XCTAssertTrue(target.usesDynamicPaths)
        XCTAssertTrue(target.requiresIndividualSelection, "Nothing here may ever be auto-selected")
        XCTAssertEqual(target.pathTemplates, StaleProjectScanner.scanRootTemplates)
    }

    func testScanRootsNeverIncludeProhibitedFolders() {
        for template in StaleProjectScanner.scanRootTemplates {
            XCTAssertFalse(template.contains("Documents"), "Documents stays off limits, always")
            XCTAssertFalse(template.contains("Desktop"), "Desktop stays off limits, always")
        }
    }

    func testResolvedArtifactValidatesAndForeignPathsDoNot() throws {
        let artifact = try makeProject("validated-app", ageDays: 90)
        let validator = SafetyValidator(
            fileManager: fileManager,
            homeDirectory: tempHome,
            bootVolumeURL: tempHome,
            allowedTargets: [target]
        )
        let roots = validator.resolveAllowlistedPaths(for: target)
        XCTAssertEqual(roots, [artifact.path], "The validator resolves exactly the stale artifacts")
        XCTAssertNil(validator.validateDeletionPath(artifact.path, for: target, allowlistedRoots: roots).error)
        // The project itself, its sources, and anything else must be refused.
        let project = artifact.deletingLastPathComponent()
        XCTAssertNotNil(validator.validateDeletionPath(project.path, for: target, allowlistedRoots: roots).error)
        XCTAssertNotNil(validator.validateDeletionPath(
            project.appendingPathComponent("package.json").path, for: target, allowlistedRoots: roots).error)
    }

    func testProjectTouchedBetweenScanAndDeleteIsRefusedAtDeleteTime() throws {
        let artifact = try makeProject("reawakened-app", ageDays: 90)
        let validator = SafetyValidator(
            fileManager: fileManager,
            homeDirectory: tempHome,
            bootVolumeURL: tempHome,
            allowedTargets: [target]
        )
        XCTAssertEqual(validator.resolveAllowlistedPaths(for: target), [artifact.path])

        // The user starts working on the project again after the scan.
        let project = artifact.deletingLastPathComponent()
        fileManager.createFile(atPath: project.appendingPathComponent("index.js").path, contents: Data())

        // Delete-time validation re-resolves, the project is no longer stale, and
        // the artifact is refused. Staleness is enforced at the moment of deletion.
        XCTAssertNotNil(validator.validateDeletionPath(artifact.path, for: target).error)
    }

    func testEngineScanProducesReadableDisplayNamesAndNoPreselection() async throws {
        let artifact = try makeProject("scan-app", ageDays: 90)
        let validator = SafetyValidator(
            fileManager: fileManager,
            homeDirectory: tempHome,
            bootVolumeURL: tempHome,
            allowedTargets: [target]
        )
        let engine = CleanerEngine(
            fileManager: fileManager,
            validator: validator,
            sizeCalculator: SizeCalculator(fileManager: fileManager),
            diskMonitor: DiskSpaceMonitor(fileManager: fileManager),
            deletionLog: InMemoryDeletionLogStore(),
            homeDirectory: tempHome
        )
        let result = await engine.scanTarget(target, options: CleanerOptions())
        XCTAssertEqual(result.resolvedPaths.count, 1)
        let resolved = try XCTUnwrap(result.resolvedPaths.first)
        XCTAssertEqual(resolved.path, artifact.path)
        XCTAssertEqual(resolved.displayName, "scan-app/node_modules")
        XCTAssertFalse(resolved.isSelected, "Deep manual-pick items start unselected")
        XCTAssertGreaterThan(resolved.estimatedBytes, 0)
        XCTAssertNotNil(resolved.lastModified)
    }
}
