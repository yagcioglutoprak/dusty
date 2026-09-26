import XCTest
@testable import CleanerEngine

/// The advisor decides which apps the memory screen offers to quit. A wrong
/// "yes" costs someone their terminal session or their call, so the rules are
/// conservative and every one of them is pinned here.
final class MemoryAdvisorTests: XCTestCase {
    private let mb: Int64 = 1_048_576
    private let hour: TimeInterval = 3600
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func candidate(
        _ id: String,
        bundleID: String? = nil,
        mbs: Int64 = 1_000,
        frontmost: Bool = false,
        idleHours: Double? = 3,
        audio: Bool = false,
        mic: Bool = false
    ) -> MemoryCandidate {
        MemoryCandidate(
            id: id,
            bundleIdentifier: bundleID ?? "com.example.\(id)",
            footprintBytes: mbs * mb,
            isFrontmost: frontmost,
            lastActiveAt: idleHours.map { now.addingTimeInterval(-$0 * hour) },
            isPlayingAudio: audio,
            isUsingMicrophone: mic
        )
    }

    private func suggested(_ candidates: [MemoryCandidate], trackingHours: Double = 10, audioKnown: Bool = true) -> Set<String> {
        MemoryAdvisor.suggestedIDs(
            candidates: candidates,
            now: now,
            trackingSince: now.addingTimeInterval(-trackingHours * hour),
            audioActivityKnown: audioKnown
        )
    }

    func testBigIdleBackgroundAppIsSuggested() {
        XCTAssertEqual(suggested([candidate("slack")]), ["slack"])
    }

    func testFrontmostAppIsNeverSuggested() {
        XCTAssertTrue(suggested([candidate("xcode", frontmost: true)]).isEmpty)
    }

    func testRecentlyUsedAppIsNotSuggested() {
        XCTAssertTrue(suggested([candidate("notion", idleHours: 0.5)]).isEmpty)
        XCTAssertEqual(suggested([candidate("notion", idleHours: 1)]), ["notion"], "Exactly the threshold counts as idle")
    }

    func testSmallAppIsNotWorthSuggesting() {
        XCTAssertTrue(suggested([candidate("notes", mbs: 120)]).isEmpty)
    }

    func testAppMakingSoundIsInUse() {
        XCTAssertTrue(suggested([candidate("chrome", audio: true)]).isEmpty, "Playing audio in a background tab")
        XCTAssertTrue(suggested([candidate("slack", mic: true)]).isEmpty, "On a huddle")
    }

    func testNeverSuggestedAppsStayOffTheList() {
        let risky = ["com.apple.Terminal", "com.googlecode.iterm2", "com.docker.docker", "us.zoom.xos", "com.apple.FaceTime"]
        let candidates = risky.map { candidate($0, bundleID: $0) }
        XCTAssertTrue(suggested(candidates).isEmpty)
    }

    func testMediaPlayersAreSkippedOnlyWhenAudioIsUnknown() {
        let music = candidate("music", bundleID: "com.apple.Music")
        XCTAssertTrue(suggested([music], audioKnown: false).isEmpty, "Might be playing, and we cannot tell")
        XCTAssertEqual(suggested([music], audioKnown: true), ["music"], "Known silent: fair game")
    }

    func testNeverActiveAppCountsAsIdleSinceTrackingStarted() {
        let unseen = candidate("figma", idleHours: nil)
        XCTAssertTrue(suggested([unseen], trackingHours: 0.25).isEmpty,
                      "Dusty just started: it has not watched long enough to call anything idle")
        XCTAssertEqual(suggested([unseen], trackingHours: 2), ["figma"])
    }

    func testCustomIdleThreshold() {
        let app = candidate("mail", idleHours: 1.5)
        let longer = MemoryAdvisor.suggestedIDs(
            candidates: [app], now: now, trackingSince: now.addingTimeInterval(-10 * hour),
            idleThreshold: 2 * hour, audioActivityKnown: true
        )
        XCTAssertTrue(longer.isEmpty)
    }

    func testAppWithoutBundleIdentifierStillFollowsTheRules() {
        let anonymous = MemoryCandidate(id: "x", bundleIdentifier: nil, footprintBytes: 900 * mb,
                                        isFrontmost: false, lastActiveAt: now.addingTimeInterval(-5 * hour))
        XCTAssertEqual(suggested([anonymous]), ["x"])
    }
}

/// Growth is reported only when an app has climbed a lot, relative to where it
/// started, over a long enough stretch. Relaunching or quitting starts over.
final class MemoryFootprintHistoryTests: XCTestCase {
    private let mb: Int64 = 1_048_576
    private let minute: TimeInterval = 60
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func history(_ readings: [(minutes: Double, mbs: Int64)], id: String = "slack", pid: Int32 = 42) -> MemoryFootprintHistory {
        var history = MemoryFootprintHistory()
        for reading in readings {
            history.record([(id: id, generation: pid, bytes: reading.mbs * mb)],
                           at: start.addingTimeInterval(reading.minutes * minute))
        }
        return history
    }

    func testSteadyClimbIsReported() throws {
        let h = history([(0, 600), (30, 800), (60, 1_100), (90, 1_500)])
        let growth = try XCTUnwrap(h.growth(for: "slack", now: start.addingTimeInterval(90 * minute)))
        XCTAssertEqual(growth.fromBytes, 600 * mb)
        XCTAssertEqual(growth.toBytes, 1_500 * mb)
        XCTAssertEqual(growth.grownBytes, 900 * mb)
        XCTAssertEqual(growth.since, start)
    }

    func testSmallGrowthIsNoise() {
        let h = history([(0, 2_000), (60, 2_400)])
        XCTAssertNil(h.growth(for: "slack", now: start.addingTimeInterval(60 * minute)))
    }

    func testLargeButProportionallySmallGrowthIsNotReported() {
        // 6 GB to 6.8 GB: a big app doing big-app things.
        let h = history([(0, 6_000), (60, 6_800)])
        XCTAssertNil(h.growth(for: "slack", now: start.addingTimeInterval(60 * minute)))
    }

    func testBurstInsideTheMinimumSpanIsNotATrend() {
        let h = history([(0, 400), (10, 1_600)])
        XCTAssertNil(h.growth(for: "slack", now: start.addingTimeInterval(10 * minute)))
    }

    func testBaselineIsTheLowestEligibleReading() throws {
        let h = history([(0, 900), (20, 500), (60, 1_400)])
        let growth = try XCTUnwrap(h.growth(for: "slack", now: start.addingTimeInterval(60 * minute)))
        XCTAssertEqual(growth.fromBytes, 500 * mb)
    }

    func testGenerationTellsARelaunchApart() {
        let h = history([(0, 500)], pid: 42)
        XCTAssertEqual(h.generation(for: "slack"), 42)
        XCTAssertNil(h.generation(for: "chrome"))
    }

    func testRelaunchStartsTheHistoryOver() {
        var h = history([(0, 500), (60, 1_500)])
        h.record([(id: "slack", generation: 99, bytes: 1_600 * mb)], at: start.addingTimeInterval(61 * minute))
        XCTAssertEqual(h.series(for: "slack").count, 1)
        XCTAssertNil(h.growth(for: "slack", now: start.addingTimeInterval(61 * minute)))
    }

    func testQuitAppLosesItsHistory() {
        var h = history([(0, 500), (60, 1_500)])
        h.record([(id: "chrome", generation: 7, bytes: 100 * mb)], at: start.addingTimeInterval(65 * minute))
        XCTAssertTrue(h.series(for: "slack").isEmpty)
        XCTAssertNil(h.growth(for: "slack", now: start.addingTimeInterval(65 * minute)))
    }

    func testReadingsOlderThanTheWindowAreDropped() {
        let h = history([(0, 300), (420, 1_500)])
        XCTAssertEqual(h.series(for: "slack").count, 1)
        XCTAssertNil(h.growth(for: "slack", now: start.addingTimeInterval(420 * minute)))
    }

    func testUnknownAppHasNoGrowth() {
        XCTAssertNil(MemoryFootprintHistory().growth(for: "nope", now: start))
    }
}

/// A "memory is running low" notification is loud, so it has to be earned:
/// sustained pressure, one per episode, and never twice inside the cooldown.
final class MemoryAlertPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let minute: TimeInterval = 60

    private func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * minute) }

    func testNormalPressureNeverAlerts() {
        XCTAssertFalse(MemoryAlertPolicy.shouldAlert(pressure: .normal, elevatedSince: ago(600),
                                                     criticalSince: nil, lastAlertAt: nil, now: now))
    }

    func testSustainedCriticalAlerts() {
        XCTAssertTrue(MemoryAlertPolicy.shouldAlert(pressure: .critical, elevatedSince: ago(3),
                                                    criticalSince: ago(3), lastAlertAt: nil, now: now))
    }

    func testBriefCriticalSpikeDoesNotAlert() {
        XCTAssertFalse(MemoryAlertPolicy.shouldAlert(pressure: .critical, elevatedSince: ago(1),
                                                     criticalSince: ago(1), lastAlertAt: nil, now: now))
    }

    func testWarningHasToHoldMuchLonger() {
        XCTAssertFalse(MemoryAlertPolicy.shouldAlert(pressure: .warning, elevatedSince: ago(10),
                                                     criticalSince: nil, lastAlertAt: nil, now: now))
        XCTAssertTrue(MemoryAlertPolicy.shouldAlert(pressure: .warning, elevatedSince: ago(25),
                                                    criticalSince: nil, lastAlertAt: nil, now: now))
    }

    func testOneAlertPerEpisode() {
        XCTAssertFalse(MemoryAlertPolicy.shouldAlert(pressure: .critical, elevatedSince: ago(600),
                                                     criticalSince: ago(600), lastAlertAt: ago(590), now: now))
    }

    func testNewEpisodeInsideTheCooldownStaysQuiet() {
        XCTAssertFalse(MemoryAlertPolicy.shouldAlert(pressure: .critical, elevatedSince: ago(30),
                                                     criticalSince: ago(30), lastAlertAt: ago(120), now: now))
    }

    func testNewEpisodeAfterTheCooldownAlertsAgain() {
        XCTAssertTrue(MemoryAlertPolicy.shouldAlert(pressure: .critical, elevatedSince: ago(30),
                                                    criticalSince: ago(30), lastAlertAt: ago(7 * 60), now: now))
    }

    func testMissingEpisodeStartNeverAlerts() {
        XCTAssertFalse(MemoryAlertPolicy.shouldAlert(pressure: .critical, elevatedSince: nil,
                                                     criticalSince: ago(10), lastAlertAt: nil, now: now))
    }
}
