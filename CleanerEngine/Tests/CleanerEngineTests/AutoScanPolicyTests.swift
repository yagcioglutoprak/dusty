import XCTest
@testable import CleanerEngine

/// The background scanner's "should I scan right now?" decision, kept pure so it can be
/// tested without timers or notifications. The app's controller is thin glue over this.
final class AutoScanPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    private func decide(
        _ trigger: AutoScanTrigger,
        lastScanAt: Date? = nil,
        isUserScanning: Bool = false,
        isCleaning: Bool = false,
        lowPowerMode: Bool = false,
        cooldown: TimeInterval = 120
    ) -> Bool {
        AutoScanPolicy.shouldScan(
            trigger: trigger, now: now, lastScanAt: lastScanAt,
            isUserScanning: isUserScanning, isCleaning: isCleaning,
            lowPowerMode: lowPowerMode, cooldown: cooldown
        )
    }

    func testNeverScansWhileUserScanOrCleanInProgress() {
        XCTAssertFalse(decide(.periodic, isUserScanning: true))
        XCTAssertFalse(decide(.periodic, isCleaning: true))
        XCTAssertFalse(decide(.lowDisk, isCleaning: true), "Even the urgent trigger must not fight an active clean")
    }

    func testFirstLaunchScansEvenWithNoPriorScan() {
        XCTAssertTrue(decide(.launch, lastScanAt: nil))
    }

    func testCooldownSuppressesRepeatScans() {
        let recent = now.addingTimeInterval(-30) // 30s ago, inside the 120s cooldown
        XCTAssertFalse(decide(.periodic, lastScanAt: recent))
        XCTAssertFalse(decide(.wake, lastScanAt: recent))
    }

    func testScansOnceCooldownHasElapsed() {
        let old = now.addingTimeInterval(-200) // older than cooldown
        XCTAssertTrue(decide(.periodic, lastScanAt: old))
    }

    func testLowPowerModeSuppressesNonUrgentTriggers() {
        XCTAssertFalse(decide(.periodic, lowPowerMode: true))
        XCTAssertFalse(decide(.freeSpaceDrop, lowPowerMode: true))
    }

    func testLowDiskTriggerPreemptsCooldownAndLowPower() {
        let recent = now.addingTimeInterval(-5)
        XCTAssertTrue(decide(.lowDisk, lastScanAt: recent, lowPowerMode: true),
                      "A low-disk crossing must force a fresh scan regardless of cooldown or power state")
    }
}
