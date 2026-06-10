import Foundation

/// Runs an external command with a hard timeout and concurrent pipe draining.
///
/// Two failure modes of plain `Process` + `waitUntilExit` are handled here:
/// - A wedged tool (hung Docker daemon, stuck `simctl`) blocks `waitUntilExit`
///   forever and the scan never finishes. The timeout terminates the process
///   (SIGTERM, then SIGKILL if ignored) and the call returns nil.
/// - Reading a pipe only after `waitUntilExit` deadlocks once the child writes
///   more than the ~64 KB pipe buffer. Both pipes are drained on background
///   threads while waiting, so output size can never wedge the parent.
enum ProcessRunner {
    struct Output {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// Lock-guarded byte buffer the drain threads write into. The dispatch group
    /// wait orders the final read after both writes, the lock covers the writes.
    private final class DrainBox: @unchecked Sendable {
        private var storage = Data()
        private let lock = NSLock()

        func store(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            storage = data
        }

        var text: String {
            lock.lock(); defer { lock.unlock() }
            return String(data: storage, encoding: .utf8) ?? ""
        }
    }

    /// Run `executablePath` with `arguments`, killing it after `timeout` seconds.
    /// Returns nil when the binary cannot launch or the timeout elapses.
    static func run(
        _ executablePath: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> Output? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        let outBox = DrainBox()
        let errBox = DrainBox()
        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        let drained = DispatchGroup()
        let drainQueue = DispatchQueue(label: "sh.toprak.dusty.process-drain", attributes: .concurrent)
        drained.enter()
        drainQueue.async {
            outBox.store(outHandle.readDataToEndOfFile())
            drained.leave()
        }
        drained.enter()
        drainQueue.async {
            errBox.store(errHandle.readDataToEndOfFile())
            drained.leave()
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 2)
            }
        }
        // Once the process is dead the pipes hit EOF, so this wait is bounded.
        drained.wait()

        if timedOut { return nil }
        return Output(status: process.terminationStatus, stdout: outBox.text, stderr: errBox.text)
    }
}
