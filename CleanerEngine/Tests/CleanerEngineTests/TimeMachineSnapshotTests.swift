import XCTest
@testable import CleanerEngine

/// Time Machine local snapshots are a Deep, manual-select target. The parser must offer
/// ONLY `com.apple.TimeMachine.*` snapshots and never `com.apple.os.update-*` ones, since
/// deleting an OS-update snapshot breaks update rollback. `tmutil` carries no real
/// filesystem path, so the action is an external command (path validation is skipped).
final class TimeMachineSnapshotTests: XCTestCase {
    func testParsesOnlyTimeMachineSnapshotsAndExtractsDateToken() {
        let output = """
        Snapshots for volume group containing disk /:
        com.apple.TimeMachine.2026-06-03-120000.local
        com.apple.TimeMachine.2026-05-28-093000.local
        com.apple.os.update-4A7DEA7F74D917BA8929B941B5A5BD20
        com.apple.os.update-MSUPrepareUpdate
        """
        let snaps = TimeMachineSnapshotHelper.parseSnapshots(from: output)

        XCTAssertEqual(snaps.count, 2, "Only Time Machine snapshots are offered")
        XCTAssertEqual(snaps.map(\.dateToken), ["2026-06-03-120000", "2026-05-28-093000"])
        XCTAssertFalse(snaps.contains { $0.name.contains("os.update") }, "OS-update snapshots must never be offered")
        XCTAssertTrue(snaps.allSatisfy { !$0.displayName.isEmpty }, "Each snapshot needs a human-readable label")
    }

    func testIgnoresEmptyAndOsUpdateOnlyOutput() {
        XCTAssertTrue(TimeMachineSnapshotHelper.parseSnapshots(from: "").isEmpty)
        let osOnly = """
        Snapshots for volume group containing disk /:
        com.apple.os.update-ABC
        com.apple.os.update-DEF
        """
        XCTAssertTrue(TimeMachineSnapshotHelper.parseSnapshots(from: osOnly).isEmpty,
                      "A machine with only OS-update snapshots offers nothing")
    }

    func testTmutilSnapshotActionIsExternalCommand() {
        XCTAssertTrue(CleanupAction.tmutilDeleteSnapshot.isExternalCommand,
                      "Snapshots have no filesystem path, so path validation must be skipped")
    }

    func testSnapshotTargetIsDeepAndManualSelect() {
        let t = CleanupTargetRegistry.all.first { $0.id == "time-machine-snapshots" }
        let target = try! XCTUnwrap(t)
        XCTAssertEqual(target.level, .deep, "Snapshots are a backup safety net: Deep level only")
        XCTAssertEqual(target.action, .tmutilDeleteSnapshot)
        XCTAssertTrue(target.requiresIndividualSelection, "User must pick snapshots individually")
        XCTAssertTrue(target.usesDynamicPaths)
    }
}
