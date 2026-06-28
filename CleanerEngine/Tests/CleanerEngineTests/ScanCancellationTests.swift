import XCTest
@testable import CleanerEngine

/// A cancelled scan must stop walking directories promptly, not finish the walk
/// and discard the result. The walk loops check `Task.isCancelled` per entry, so
/// running them inside an already-cancelled task must bail at the first item.
/// (Deterministic on purpose: no sleeps, no wall-clock assertions.)
final class ScanCancellationTests: XCTestCase {
    var tempHome: URL!
    var fileManager: FileManager!

    override func setUpWithError() throws {
        fileManager = FileManager.default
        tempHome = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: tempHome)
    }

    private func makePopulatedCacheRoot(files: Int) throws -> URL {
        let cacheRoot = tempHome.appendingPathComponent("Library/Caches/com.big.app")
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        for i in 0..<files {
            try Data(repeating: 0x55, count: 128).write(to: cacheRoot.appendingPathComponent("chunk-\(i).bin"))
        }
        return cacheRoot
    }

    /// Runs `body` inside a task that is guaranteed to be cancelled before the work starts.
    ///
    /// Suspends on a real cancellation handler rather than spinning on
    /// `Task.yield()`. The spin form livelocks under a cooperative executor:
    /// when the executor is contended (CI macOS runners under load), the
    /// yielding task gets rescheduled without the cancel signal ever being
    /// delivered, so `Task.isCancelled` is never observed and the test hangs.
    /// `withTaskCancellationHandler` resumes the boxed continuation exactly
    /// once when cancellation lands, deterministically, with no polling.
    private func runCancelled<T: Sendable>(_ body: @Sendable @escaping () -> T) async -> T {
        let gate = CancellationGate()
        let task = Task { () -> T in
            await gate.waitForCancellation()
            return body()
        }
        task.cancel()
        return await task.value
    }

    func testCancelledDirectoryWalkBailsAtFirstEntry() async throws {
        let cacheRoot = try makePopulatedCacheRoot(files: 50)
        let calculator = SizeCalculator(fileManager: fileManager)

        let fullSize = calculator.directoryAllocatedSize(at: cacheRoot)
        XCTAssertGreaterThan(fullSize, 0, "Precondition: the tree has real size")

        let cancelledSize = await runCancelled { calculator.directoryAllocatedSize(at: cacheRoot) }
        XCTAssertEqual(cancelledSize, 0, "A cancelled walk must stop before summing anything")
    }

    func testCancelledScanReturnsNoPaths() async throws {
        _ = try makePopulatedCacheRoot(files: 10)
        let validator = SafetyValidator(
            fileManager: fileManager,
            homeDirectory: tempHome,
            bootVolumeURL: tempHome,
            allowedTargets: CleanupTargetRegistry.level1
        )
        let engine = CleanerEngine(
            fileManager: fileManager,
            validator: validator,
            sizeCalculator: SizeCalculator(fileManager: fileManager),
            diskMonitor: DiskSpaceMonitor(fileManager: fileManager),
            deletionLog: InMemoryDeletionLogStore(),
            homeDirectory: tempHome
        )

        let gate = CancellationGate()
        let task = Task { () -> FullScanResult in
            await gate.waitForCancellation()
            return await engine.scan(levels: [.safe])
        }
        task.cancel()
        let result = await task.value

        let pathCount = result.levelResults.values
            .flatMap(\.targetResults)
            .flatMap(\.resolvedPaths)
            .count
        XCTAssertEqual(pathCount, 0, "A scan that starts cancelled must not report any paths")
    }

    func testCancelledWalkNeverPoisonsTheSizeCache() async throws {
        let cacheRoot = try makePopulatedCacheRoot(files: 50)
        let cache = SizeCache()
        let calculator = SizeCalculator(fileManager: fileManager, cache: cache)

        _ = await runCancelled { calculator.allocatedSize(at: cacheRoot.path, policy: .cached) }

        // A later cached read must re-walk and return the real size, not a cancelled partial.
        let size = calculator.allocatedSize(at: cacheRoot.path, policy: .cached)
        let fresh = calculator.allocatedSize(at: cacheRoot.path, policy: .fresh)
        XCTAssertEqual(size, fresh, "Cancelled partial totals must never be served from the cache")
        XCTAssertGreaterThan(size, 0)
    }
}

/// A one-shot gate that suspends a task until it is cancelled, deterministically.
///
/// Per-instance (not static), so concurrent tests do not share state. The
/// continuation is stored under a lock; if cancellation lands before the
/// operation registers its continuation, the flag is set and the continuation
/// (when it arrives) resumes immediately. `resume()` is called exactly once.
/// `@unchecked Sendable`: both stored properties are touched only under the
/// lock, so the type is safe to share across tasks despite the mutable state.
private final class CancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var cancelled = false

    func waitForCancellation() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                self.lock.lock()
                if self.cancelled {
                    self.lock.unlock()
                    cont.resume()
                } else {
                    self.continuation = cont
                    self.lock.unlock()
                }
            }
        } onCancel: {
            self.resume()
        }
    }

    private func resume() {
        lock.lock()
        let cont = continuation
        continuation = nil
        cancelled = true
        lock.unlock()
        cont?.resume()
    }
}
