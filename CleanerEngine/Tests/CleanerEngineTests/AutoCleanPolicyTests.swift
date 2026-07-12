import XCTest
@testable import CleanerEngine

/// The unattended cleaner's "should I delete right now?" decision. Deleting is the one
/// thing this app must never do at the wrong moment, so every gate gets its own test.
final class AutoCleanPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let tenGB: Int64 = 10 * 1_073_741_824

    private func decide(
        _ trigger: AutoCleanTrigger,
        scheduleEnabled: Bool = true,
        scheduleIntervalDays: Int = 7,
        lastScheduledCleanAt: Date? = nil,
        reactiveEnabled: Bool = true,
        freeBytes: Int64 = 5 * 1_073_741_824,
        reactiveThresholdBytes: Int64 = 10 * 1_073_741_824,
        lastReactiveCleanAt: Date? = nil,
        isBusy: Bool = false,
        lowPowerMode: Bool = false,
        dryRunDefault: Bool = false
    ) -> Bool {
        AutoCleanPolicy.shouldClean(
            trigger: trigger, now: now,
            scheduleEnabled: scheduleEnabled,
            scheduleIntervalDays: scheduleIntervalDays,
            lastScheduledCleanAt: lastScheduledCleanAt,
            reactiveEnabled: reactiveEnabled,
            freeBytes: freeBytes,
            reactiveThresholdBytes: reactiveThresholdBytes,
            lastReactiveCleanAt: lastReactiveCleanAt,
            isBusy: isBusy, lowPowerMode: lowPowerMode, dryRunDefault: dryRunDefault
        )
    }

    // MARK: Shared gates

    func testNeverCleansWhileBusy() {
        let due = now.addingTimeInterval(-8 * 86_400)
        XCTAssertFalse(decide(.scheduled, lastScheduledCleanAt: due, isBusy: true))
        XCTAssertFalse(decide(.lowDisk, isBusy: true),
                       "Low disk is not urgent enough to fight an active scan or clean")
    }

    func testLowPowerModeBlocksBothTriggers() {
        let due = now.addingTimeInterval(-8 * 86_400)
        XCTAssertFalse(decide(.scheduled, lastScheduledCleanAt: due, lowPowerMode: true))
        XCTAssertFalse(decide(.lowDisk, lowPowerMode: true),
                       "Unlike the scanner, deleting never preempts battery saver")
    }

    func testDryRunDefaultBlocksBothTriggers() {
        let due = now.addingTimeInterval(-8 * 86_400)
        XCTAssertFalse(decide(.scheduled, lastScheduledCleanAt: due, dryRunDefault: true))
        XCTAssertFalse(decide(.lowDisk, dryRunDefault: true))
    }

    // MARK: Scheduled trigger

    func testScheduledCleanRunsWhenPeriodElapsed() {
        XCTAssertTrue(decide(.scheduled, lastScheduledCleanAt: now.addingTimeInterval(-8 * 86_400)))
    }

    func testScheduledCleanWaitsOutThePeriod() {
        XCTAssertFalse(decide(.scheduled, lastScheduledCleanAt: now.addingTimeInterval(-3 * 86_400)))
    }

    func testScheduledCleanNeverFiresWithoutABaseline() {
        XCTAssertFalse(decide(.scheduled, lastScheduledCleanAt: nil),
                       "Flipping the toggle must start the period, not fire a clean")
    }

    func testScheduledCleanRespectsDisabledToggle() {
        let due = now.addingTimeInterval(-8 * 86_400)
        XCTAssertFalse(decide(.scheduled, scheduleEnabled: false, lastScheduledCleanAt: due))
    }

    func testScheduleIntervalClampsToAtLeastOneDay() {
        let halfDay = now.addingTimeInterval(-12 * 3600)
        XCTAssertFalse(decide(.scheduled, scheduleIntervalDays: 0, lastScheduledCleanAt: halfDay))
        XCTAssertTrue(decide(.scheduled, scheduleIntervalDays: 0, lastScheduledCleanAt: now.addingTimeInterval(-86_401)))
    }

    // MARK: Reactive (low disk) trigger

    func testReactiveCleanRunsBelowThreshold() {
        XCTAssertTrue(decide(.lowDisk, freeBytes: tenGB - 1, reactiveThresholdBytes: tenGB))
    }

    func testReactiveCleanRefusesAtOrAboveThreshold() {
        XCTAssertFalse(decide(.lowDisk, freeBytes: tenGB, reactiveThresholdBytes: tenGB))
        XCTAssertFalse(decide(.lowDisk, freeBytes: tenGB * 2, reactiveThresholdBytes: tenGB))
    }

    func testReactiveCleanRespectsDisabledToggle() {
        XCTAssertFalse(decide(.lowDisk, reactiveEnabled: false))
    }

    func testReactiveCooldownStopsARetryLoop() {
        // If the last reactive clean could not push free space back over the line, the
        // disk reads "low" on every sampler tick. The cooldown is what stops that from
        // becoming a delete attempt every few seconds.
        let recent = now.addingTimeInterval(-3600)
        XCTAssertFalse(decide(.lowDisk, lastReactiveCleanAt: recent))
        let old = now.addingTimeInterval(-AutoCleanPolicy.reactiveCooldown - 1)
        XCTAssertTrue(decide(.lowDisk, lastReactiveCleanAt: old))
    }

    func testReactiveCleanRefusesANonPositiveThreshold() {
        XCTAssertFalse(decide(.lowDisk, freeBytes: -1, reactiveThresholdBytes: 0))
    }

    func testTriggersAreIndependent() {
        // A due schedule must not leak into the reactive decision and vice versa.
        XCTAssertFalse(decide(.lowDisk, lastScheduledCleanAt: now.addingTimeInterval(-30 * 86_400),
                              freeBytes: tenGB * 3))
        XCTAssertTrue(decide(.scheduled, lastScheduledCleanAt: now.addingTimeInterval(-8 * 86_400),
                             reactiveEnabled: false, freeBytes: tenGB * 3))
    }
}
