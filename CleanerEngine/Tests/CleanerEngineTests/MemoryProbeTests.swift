import XCTest
@testable import CleanerEngine

/// Live reads against the machine running the tests. The figures themselves
/// change from run to run, so these check shape and sanity: the kernel answered,
/// nothing exceeds physical memory, and this very process shows up.
final class MemoryProbeTests: XCTestCase {
    func testSystemSnapshotIsSane() throws {
        let snapshot = try XCTUnwrap(MemoryMonitor().snapshot())
        XCTAssertEqual(snapshot.totalBytes, Int64(ProcessInfo.processInfo.physicalMemory))
        XCTAssertGreaterThan(snapshot.usedBytes, 0)
        XCTAssertGreaterThan(snapshot.wiredBytes, 0, "The kernel always wires some memory")
        XCTAssertLessThanOrEqual(snapshot.usedBytes + snapshot.cachedFilesBytes, snapshot.totalBytes)
        XCTAssertGreaterThanOrEqual(snapshot.swapTotalBytes, snapshot.swapUsedBytes)
    }

    func testPressureLevelIsReadable() {
        XCTAssertNotNil(MemoryMonitor.sysctlInt32("kern.memorystatus_vm_pressure_level"))
    }

    func testThisProcessIsSampledWithItsFootprint() throws {
        let samples = ProcessMemoryScanner.sample()
        let me = try XCTUnwrap(samples.first { $0.pid == getpid() }, "The test runner is owned by this user")
        XCTAssertGreaterThan(me.footprintBytes, 0)
        XCTAssertTrue(me.executablePath.hasPrefix("/"))
        XCTAssertFalse(samples.contains { $0.pid <= 1 }, "Kernel and launchd are never sampled")
    }

    func testSamplesGroupWithoutLosingMemory() {
        let samples = ProcessMemoryScanner.sample()
        let groups = AppMemoryGrouping.group(samples)
        let sampled = samples.reduce(Int64(0)) { $0 + $1.footprintBytes }
        let grouped = groups.reduce(Int64(0)) { $0 + $1.footprintBytes }
        XCTAssertEqual(grouped, sampled, "Grouping moves memory between lines, never drops or doubles it")
        XCTAssertEqual(groups.reduce(0) { $0 + $1.processCount }, samples.filter { $0.footprintBytes > 0 }.count)
    }

    func testAudioProbeAnswersOrStepsAside() {
        // Nil on macOS before 14.2; otherwise a (possibly empty) set of pids.
        if let activity = AudioActivityProbe.current() {
            XCTAssertFalse(activity.outputPIDs.contains(0))
            XCTAssertFalse(activity.inputPIDs.contains(0))
        }
    }
}
