import XCTest
@testable import CleanerEngine

/// AI model stores in ~/.cache (Hugging Face, PyTorch hub, Whisper, LM Studio) are
/// deliberate multi-gigabyte downloads. The Developer ~/.cache sweep must never list,
/// select or delete them, whether through a scan, a stale selection, or a clear of
/// ~/.cache itself. Only the opt-in Deep target "AI Model Caches" reaches the models.
final class AIModelStoreTests: XCTestCase {
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

    private func home(_ relative: String) -> String {
        tempHome.appendingPathComponent(relative).path
    }

    private var validator: SafetyValidator {
        SafetyValidator(fileManager: fileManager, homeDirectory: tempHome, bootVolumeURL: tempHome)
    }

    private func makeEngine() -> CleanerEngine {
        CleanerEngine(
            fileManager: fileManager,
            validator: validator,
            sizeCalculator: SizeCalculator(fileManager: fileManager),
            diskMonitor: DiskSpaceMonitor(fileManager: fileManager),
            deletionLog: InMemoryDeletionLogStore(),
            homeDirectory: tempHome
        )
    }

    private func makeFiles(_ relatives: [String]) throws {
        for relative in relatives {
            let url = tempHome.appendingPathComponent(relative)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0xAB, count: 1024).write(to: url)
        }
    }

    private let modelStoreFiles = [
        ".cache/huggingface/hub/x",
        ".cache/lm-studio/models/x",
        ".cache/torch/hub/x",
        ".cache/whisper/x",
    ]

    // MARK: - Developer ~/.cache sweep

    func testDeveloperScanSelectsCachesButNotModelStores() async throws {
        try makeFiles(modelStoreFiles + [".cache/pip-like/y"])

        let result = await makeEngine().scanTarget(target("xdg-cache"), options: CleanerOptions())

        XCTAssertEqual(result.resolvedPaths.filter(\.isSelected).map(\.path), [home(".cache/pip-like")])
        XCTAssertEqual(result.resolvedPaths.map(\.path), [home(".cache/pip-like")],
                       "Model stores are not even listed, so they never count toward the clean")
    }

    func testValidatorRefusesModelStoresForXDGCache() {
        let t = target("xdg-cache")
        for relative in [
            ".cache/huggingface", ".cache/huggingface/hub/x", ".cache/huggingface/token",
            ".cache/lm-studio", ".cache/torch", ".cache/whisper",
            ".cache/HuggingFace", ".cache/Torch/hub",
        ] {
            guard case .failure(.prohibitedPath) = validator.validateDeletionPath(home(relative), for: t) else {
                XCTFail("\(relative) must be refused for xdg-cache")
                continue
            }
        }
        XCTAssertNil(validator.validateDeletionPath(home(".cache/pip-like"), for: t).error)
        XCTAssertNil(validator.validateDeletionPath(home(".cache/huggingface-cli-lookalike"), for: t).error,
                     "Only the exact store folders are excluded, not every name sharing a prefix")
    }

    func testSymlinkUnderDotCacheCannotLeadIntoModelStore() throws {
        try makeFiles(modelStoreFiles)
        try fileManager.createSymbolicLink(atPath: home(".cache/hf-link"), withDestinationPath: home(".cache/huggingface"))
        XCTAssertNotNil(validator.validateDeletionPath(home(".cache/hf-link/hub"), for: target("xdg-cache")).error)
    }

    func testStaleSelectionOfModelStoreIsSkipped() async throws {
        try makeFiles(modelStoreFiles)
        let t = target("xdg-cache")
        let stale = ResolvedPath(path: home(".cache/huggingface"), displayName: "huggingface",
                                 targetID: t.id, estimatedBytes: 1024, isSelected: true)

        let result = await makeEngine().delete(paths: [stale], targets: [t], options: CleanerOptions())

        XCTAssertTrue(fileManager.fileExists(atPath: home(".cache/huggingface/hub/x")))
        XCTAssertEqual(result.skippedPaths.map { $0.path }, [home(".cache/huggingface")])
        XCTAssertEqual(result.bytesFreed, 0)
    }

    func testClearingDotCacheItselfLeavesModelStores() async throws {
        try makeFiles(modelStoreFiles + [".cache/pip-like/y"])
        let t = target("xdg-cache")
        let root = ResolvedPath(path: home(".cache"), displayName: ".cache",
                                targetID: t.id, estimatedBytes: 1024, isSelected: true)

        _ = await makeEngine().delete(paths: [root], targets: [t], options: CleanerOptions())

        XCTAssertFalse(fileManager.fileExists(atPath: home(".cache/pip-like")))
        for file in modelStoreFiles {
            XCTAssertTrue(fileManager.fileExists(atPath: home(file)), "\(file) must survive")
        }
    }

    func testEveryExclusionNamesARegisteredTargetAndSitsUnderItsRoot() {
        for (id, subpaths) in CleanupTargetRegistry.excludedSubpaths {
            let t = CleanupTargetRegistry.all.first { $0.id == id }
            XCTAssertNotNil(t, "Exclusion for unknown target \(id)")
            for subpath in subpaths {
                XCTAssertTrue(t?.pathTemplates.contains { subpath.hasPrefix($0 + "/") } ?? false,
                              "\(subpath) is outside \(id)'s roots, so excluding it does nothing")
            }
        }
    }

    // MARK: - AI Model Caches (opt-in)

    func testAIModelCachesAreDeepAndStrictlyOptIn() {
        let t = target("ai-model-caches")
        XCTAssertEqual(t.level, .deep)
        XCTAssertEqual(t.category, "AI Models")
        XCTAssertTrue(t.requiresExplicitOptIn, "Models are deliberate downloads, never auto-selected")
        XCTAssertTrue(t.needsUserSelection)
        XCTAssertFalse(t.regenerates)
        XCTAssertTrue(CleanupTargetRegistry.level3.contains { $0.id == "ai-model-caches" })
    }

    func testAIModelCachesReachOnlyTheModelFolders() {
        let t = target("ai-model-caches")
        for relative in [
            ".cache/huggingface/hub/models--org--name", ".cache/torch/hub/checkpoints",
            ".cache/whisper/large-v3.pt", ".cache/lm-studio/models/publisher", ".lmstudio/models/publisher",
        ] {
            XCTAssertNil(validator.validateDeletionPath(home(relative), for: t).error, "\(relative) must validate")
        }
        for relative in [
            ".cache/huggingface", ".cache/huggingface/token", ".cache/torch",
            ".cache/lm-studio", ".cache/lm-studio/conversations", ".lmstudio", ".lmstudio/conversations",
            ".cache/pip-like",
        ] {
            XCTAssertNotNil(validator.validateDeletionPath(home(relative), for: t).error, "\(relative) must be refused")
        }
    }

    func testAIModelCachesScanListsEachModelUnselected() async throws {
        try makeFiles([
            ".cache/huggingface/hub/models--org--a/blob",
            ".cache/huggingface/hub/models--org--b/blob",
            ".cache/huggingface/token",
            ".cache/whisper/base.pt",
        ])

        let result = await makeEngine().scanTarget(target("ai-model-caches"), options: CleanerOptions())

        XCTAssertEqual(Set(result.resolvedPaths.map(\.path)), [
            home(".cache/huggingface/hub/models--org--a"),
            home(".cache/huggingface/hub/models--org--b"),
            home(".cache/whisper/base.pt"),
        ])
        XCTAssertFalse(result.resolvedPaths.contains(where: \.isSelected), "Opt-in target must scan unselected")
    }
}
