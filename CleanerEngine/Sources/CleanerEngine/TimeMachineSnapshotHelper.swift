import Foundation

/// Lists and deletes Time Machine local snapshots via `tmutil`.
///
/// Only `com.apple.TimeMachine.*` snapshots are ever offered. `com.apple.os.update-*`
/// snapshots are deliberately excluded: deleting one breaks macOS update rollback.
enum TimeMachineSnapshotHelper {
    struct Snapshot: Sendable, Equatable {
        /// Full snapshot name as `tmutil` reports it.
        let name: String
        /// The `yyyy-MM-dd-HHmmss` token `tmutil deletelocalsnapshots` expects.
        let dateToken: String
        /// Human-readable label for the UI.
        let displayName: String
    }

    private static let prefix = "com.apple.TimeMachine."
    private static let suffix = ".local"

    /// Time Machine local snapshots on the root volume.
    static func listSnapshots() -> [Snapshot] {
        guard let output = runTmutil(arguments: ["listlocalsnapshots", "/"]) else { return [] }
        return parseSnapshots(from: output)
    }

    /// Parse `tmutil listlocalsnapshots /` output, keeping only Time Machine snapshots.
    static func parseSnapshots(from output: String) -> [Snapshot] {
        output.split(separator: "\n").compactMap { rawLine -> Snapshot? in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(prefix) else { return nil }
            let afterPrefix = String(line.dropFirst(prefix.count))
            let token = afterPrefix.hasSuffix(suffix) ? String(afterPrefix.dropLast(suffix.count)) : afterPrefix
            guard !token.isEmpty else { return nil }
            return Snapshot(name: line, dateToken: token, displayName: humanLabel(for: token))
        }
    }

    /// Delete one snapshot by date token. `tmutil` can exit 0 even on failure, so success
    /// is confirmed by re-listing and checking the snapshot is actually gone.
    @discardableResult
    static func deleteSnapshot(dateToken: String) -> Bool {
        _ = runTmutil(arguments: ["deletelocalsnapshots", dateToken])
        return !listSnapshots().contains { $0.dateToken == dateToken }
    }

    private static func humanLabel(for token: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd-HHmmss"
        guard let date = input.date(from: token) else { return token }
        let output = DateFormatter()
        output.dateStyle = .medium
        output.timeStyle = .short
        return "Snapshot from \(output.string(from: date))"
    }

    private static func runTmutil(arguments: [String]) -> String? {
        // Listing is quick; deleting a big snapshot can legitimately take minutes,
        // so the timeout is generous but still bounded.
        let timeout: TimeInterval = arguments.first == "deletelocalsnapshots" ? 300 : 30
        guard let result = ProcessRunner.run("/usr/bin/tmutil", arguments: arguments, timeout: timeout) else {
            return nil
        }
        return result.stdout
    }
}
