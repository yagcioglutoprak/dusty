import XCTest
@testable import CleanerEngine

/// Quitting an app gives back the memory of every process working for it, so
/// that is the figure the memory screen has to show: helpers roll up into their
/// app, WebKit pages into Safari, and the app's own process leads the group.
final class AppMemoryGroupingTests: XCTestCase {
    private let mb: Int64 = 1_048_576

    private func sample(_ pid: Int32, _ path: String, _ mbs: Int64, responsible: Int32? = nil) -> ProcessMemorySample {
        ProcessMemorySample(pid: pid, responsiblePID: responsible ?? pid, executablePath: path, footprintBytes: mbs * mb)
    }

    private let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    private let chromeRenderer = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/129.0/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
    private let safari = "/Applications/Safari.app/Contents/MacOS/Safari"
    private let webContent = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"

    func testHelpersNestedInsideAnAppRollUpIntoIt() throws {
        let groups = AppMemoryGrouping.group([
            sample(500, chrome, 300),
            sample(510, chromeRenderer, 700),
            sample(511, chromeRenderer, 500),
        ])
        XCTAssertEqual(groups.count, 1)
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.id, "/Applications/Google Chrome.app")
        XCTAssertEqual(group.name, "Google Chrome")
        XCTAssertEqual(group.footprintBytes, 1_500 * mb)
        XCTAssertEqual(group.pids, [500, 510, 511])
        XCTAssertEqual(group.leaderPID, 500, "The app's own process leads, not a helper")
        XCTAssertTrue(group.isApp)
    }

    func testResponsibleProcessWinsOverWhereTheBinaryLives() throws {
        // Safari's pages run in WebKit processes outside Safari.app. macOS still
        // holds Safari responsible for them, and so should the totals.
        let groups = AppMemoryGrouping.group([
            sample(700, safari, 250),
            sample(720, webContent, 900, responsible: 700),
            sample(721, webContent, 400, responsible: 700),
        ])
        let safariGroup = try XCTUnwrap(groups.first { $0.id == "/Applications/Safari.app" })
        XCTAssertEqual(safariGroup.footprintBytes, 1_550 * mb)
        XCTAssertEqual(safariGroup.processCount, 3)
        XCTAssertEqual(safariGroup.leaderPID, 700)
        XCTAssertEqual(groups.count, 1)
    }

    func testMissingResponsibleProcessFallsBackToOwnPath() throws {
        // The responsible process belongs to another user (not sampled), so the
        // process stands on its own.
        let groups = AppMemoryGrouping.group([sample(720, webContent, 900, responsible: 88)])
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.id, webContent)
        XCTAssertEqual(group.name, "com.apple.WebKit.WebContent")
        XCTAssertNil(group.bundlePath)
        XCTAssertFalse(group.isApp)
    }

    func testToolsStartedFromTerminalBelongToTerminal() throws {
        let terminal = "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
        let groups = AppMemoryGrouping.group([
            sample(300, terminal, 80),
            sample(301, "/bin/zsh", 5, responsible: 300),
            sample(302, "/opt/homebrew/bin/node", 1_200, responsible: 300),
        ])
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.id, "/System/Applications/Utilities/Terminal.app")
        XCTAssertEqual(group.footprintBytes, 1_285 * mb, "Quitting Terminal ends what runs inside it")
    }

    func testStandAloneProcessesGroupByExecutable() throws {
        let node = "/opt/homebrew/bin/node"
        let groups = AppMemoryGrouping.group([
            sample(900, node, 300),
            sample(901, node, 200),
            sample(950, "/usr/local/bin/redis-server", 50),
        ])
        XCTAssertEqual(groups.map(\.id), [node, "/usr/local/bin/redis-server"])
        XCTAssertEqual(groups[0].footprintBytes, 500 * mb)
        XCTAssertEqual(groups[0].name, "node")
        XCTAssertEqual(groups[0].leaderPID, 900)
    }

    func testExcludedAndEmptyProcessesAreDropped() {
        let groups = AppMemoryGrouping.group(
            [sample(1, safari, 100), sample(2, chrome, 0), sample(3, "/usr/bin/top", 5)],
            excludingPIDs: [1]
        )
        XCTAssertEqual(groups.map(\.id), ["/usr/bin/top"])
    }

    func testGroupsAreLargestFirstWithStableTies() {
        let groups = AppMemoryGrouping.group([
            sample(10, "/Applications/B.app/Contents/MacOS/B", 100),
            sample(11, "/Applications/A.app/Contents/MacOS/A", 100),
            sample(12, "/Applications/C.app/Contents/MacOS/C", 900),
        ])
        XCTAssertEqual(groups.map(\.name), ["C", "A", "B"])
    }

    func testLeaderFallsBackToLowestPidWithoutMainExecutable() throws {
        let groups = AppMemoryGrouping.group([
            sample(611, chromeRenderer, 10),
            sample(610, chromeRenderer, 10),
        ])
        XCTAssertEqual(try XCTUnwrap(groups.first).leaderPID, 610)
    }

    func testAppBundlePathTakesTheOutermostBundle() {
        XCTAssertEqual(AppMemoryGrouping.appBundlePath(forExecutable: chromeRenderer), "/Applications/Google Chrome.app")
        XCTAssertEqual(AppMemoryGrouping.appBundlePath(forExecutable: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"),
                       "/System/Library/CoreServices/Finder.app")
        XCTAssertNil(AppMemoryGrouping.appBundlePath(forExecutable: "/usr/bin/weird.app"),
                     "An executable merely named .app is not a bundle")
        XCTAssertNil(AppMemoryGrouping.appBundlePath(forExecutable: "/Applications/.app/Contents/MacOS/x"))
        XCTAssertNil(AppMemoryGrouping.appBundlePath(forExecutable: webContent))
    }

    func testMainExecutableTellsAppFromHelper() {
        let bundle = "/Applications/Google Chrome.app"
        XCTAssertTrue(AppMemoryGrouping.isMainExecutable(chrome, of: bundle))
        XCTAssertFalse(AppMemoryGrouping.isMainExecutable(chromeRenderer, of: bundle))
        XCTAssertFalse(AppMemoryGrouping.isMainExecutable("/Applications/Google Chrome.appx/MacOS/x", of: bundle))
    }

    func testAppNestedInsideAnotherAppKeepsItsOwnLine() throws {
        let xcode = "/Applications/Xcode.app/Contents/MacOS/Xcode"
        let simulator = "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator"
        let simHelper = "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/XPCServices/Render.app/Contents/MacOS/Render"
        let groups = AppMemoryGrouping.group([
            sample(100, xcode, 2_000),
            sample(200, simulator, 600),
            sample(201, simHelper, 150, responsible: 200),
        ], appPIDs: [100, 200])
        let xcodeGroup = try XCTUnwrap(groups.first { $0.id == "/Applications/Xcode.app" })
        let simGroup = try XCTUnwrap(groups.first { $0.id.hasSuffix("/Simulator.app") })
        XCTAssertEqual(xcodeGroup.pids, [100])
        XCTAssertEqual(xcodeGroup.leaderPID, 100)
        XCTAssertEqual(simGroup.pids, [200, 201])
        XCTAssertEqual(simGroup.leaderPID, 200)
        XCTAssertEqual(simGroup.name, "Simulator")
    }

    func testWithoutAppPIDsNestedAppsRollUpAsBefore() {
        let xcode = "/Applications/Xcode.app/Contents/MacOS/Xcode"
        let simulator = "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator"
        let groups = AppMemoryGrouping.group([sample(100, xcode, 2_000), sample(200, simulator, 600)])
        XCTAssertEqual(groups.map(\.id), ["/Applications/Xcode.app"])
    }

    func testRegisteredAppIgnoresItsResponsibleProcess() throws {
        // An app launched by another app (a login-item helper started by its
        // parent) still stands on its own once macOS runs it as an app.
        let foo = "/Applications/Foo.app/Contents/MacOS/Foo"
        let helper = "/Applications/Foo.app/Contents/Library/LoginItems/FooHelper.app/Contents/MacOS/FooHelper"
        let groups = AppMemoryGrouping.group([
            sample(10, foo, 400),
            sample(11, helper, 90, responsible: 10),
        ], appPIDs: [10, 11])
        XCTAssertEqual(Set(groups.map(\.leaderPID)), [10, 11])
        let fooGroup = try XCTUnwrap(groups.first { $0.leaderPID == 10 })
        XCTAssertEqual(fooGroup.footprintBytes, 400 * mb, "The helper's memory is not Foo's to give back")
    }

    func testInnermostBundle() {
        XCTAssertEqual(AppMemoryGrouping.innermostAppBundlePath(forExecutable: chromeRenderer),
                       "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/129.0/Helpers/Google Chrome Helper (Renderer).app")
        XCTAssertEqual(AppMemoryGrouping.innermostAppBundlePath(forExecutable: chrome), "/Applications/Google Chrome.app")
        XCTAssertNil(AppMemoryGrouping.innermostAppBundlePath(forExecutable: "/usr/bin/weird.app"))
    }
}
