import XCTest
@testable import CleanerEngine

final class DustyCLIParserTests: XCTestCase {
    func testCleanDeveloperYesParsesCommandLevelAndFlag() {
        let args = parseArgs(["clean", "--level", "developer", "--yes"])

        XCTAssertEqual(args?.command, "clean")
        XCTAssertEqual(args?.level, "developer")
        XCTAssertEqual(args?.yes, true)
        XCTAssertEqual(args?.json, false)
        XCTAssertEqual(args?.dryRun, false)
        XCTAssertEqual(args?.trash, false)
    }

    func testUnknownFlagsAreRejected() {
        XCTAssertNil(parseArgs(["clean", "--force"]))
        XCTAssertNil(parseArgs(["--force"]))
    }

    func testLevelWithoutValueIsRejected() {
        XCTAssertNil(parseArgs(["clean", "--level"]))
        XCTAssertNil(parseArgs(["clean", "--level", "--yes"]))
    }

    func testLevelAliasesResolveToExpectedLevels() {
        XCTAssertEqual(levels(from: "dev", defaultAll: false), [.developer])
        XCTAssertEqual(levels(from: "2", defaultAll: false), [.developer])
        XCTAssertEqual(levels(from: "deep", defaultAll: false), [.deep])
        XCTAssertEqual(levels(from: "3", defaultAll: false), [.deep])
        XCTAssertEqual(levels(from: "all", defaultAll: false), Set(CleanupLevel.allCases))
    }
}
