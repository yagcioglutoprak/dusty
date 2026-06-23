import XCTest
@testable import CleanerEngine

/// External commands (simctl, tmutil, docker) must never hang a scan or clean:
/// every invocation goes through ProcessRunner, which enforces a hard timeout and
/// drains pipes concurrently so big output cannot deadlock the parent.
final class ProcessRunnerTests: XCTestCase {
    func testCapturesStdoutAndExitStatus() {
        let result = ProcessRunner.run("/bin/echo", arguments: ["hello"], timeout: 10)
        XCTAssertEqual(result?.status, 0)
        XCTAssertEqual(result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testCapturesStderr() {
        // ls of a nonexistent path exits nonzero and complains on stderr.
        let result = ProcessRunner.run("/bin/ls", arguments: ["/definitely-not-a-real-path-dusty"], timeout: 10)
        XCTAssertNotNil(result)
        XCTAssertNotEqual(result?.status, 0)
        XCTAssertFalse(result?.stderr.isEmpty ?? true)
    }

    func testTimeoutKillsHungProcessAndReturnsNil() {
        let start = Date()
        let result = ProcessRunner.run("/bin/sleep", arguments: ["30"], timeout: 0.3)
        XCTAssertNil(result, "A timed-out process must report failure, not block")
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "Must return promptly after the timeout, not after the child's natural exit")
    }

    func testLargeOutputDoesNotDeadlock() {
        // 512 KB of output, far past the ~64 KB pipe buffer that deadlocks a
        // read-after-waitUntilExit implementation.
        let result = ProcessRunner.run("/bin/dd", arguments: ["if=/dev/zero", "bs=1024", "count=512"], timeout: 30)
        XCTAssertEqual(result?.status, 0)
        XCTAssertEqual(result?.stdout.utf8.count, 512 * 1024)
    }

    func testMissingBinaryReturnsNil() {
        XCTAssertNil(ProcessRunner.run("/no/such/binary", arguments: [], timeout: 5))
    }

    func testGrandchildHoldingPipeDoesNotHangDrain() {
        // The shell exits immediately but leaves a backgrounded grandchild that inherited
        // the stdout pipe and keeps its write end open. A plain readDataToEndOfFile then
        // never sees EOF and blocks until the grandchild's natural exit (~5s). The bounded
        // drain must return within the grace window instead, the exact wedge ProcessRunner
        // exists to survive.
        let start = Date()
        let result = ProcessRunner.run(
            "/bin/sh",
            arguments: ["-c", "sleep 5 & echo hi"],
            timeout: 5,
            drainGrace: 0.5
        )
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 3, "Drain must be bounded even when a grandchild keeps the pipe open")
        XCTAssertNotNil(result, "The process itself exited cleanly; only the orphan drain was slow")
    }
}
