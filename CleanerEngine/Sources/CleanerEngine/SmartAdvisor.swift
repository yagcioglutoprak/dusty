import Foundation

/// A scan-derived observation worth surfacing: leftover data from an uninstalled
/// tool, or a big cache nothing has touched in months. Advisories never select or
/// delete anything; they point, the user decides.
public struct Advisory: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    /// The cleanup target the advisory points at, so the UI can jump to it.
    public let targetID: String
    public let bytes: Int64

    public init(id: String, title: String, detail: String, targetID: String, bytes: Int64) {
        self.id = id
        self.title = title
        self.detail = detail
        self.targetID = targetID
        self.bytes = bytes
    }
}

/// Reads a finished scan and flags what a person would spot: data left behind by
/// tools that are no longer installed, and large caches that have sat untouched for
/// months. Injected directories keep it fully testable without a real /Applications.
public struct SmartAdvisor: @unchecked Sendable {
    private let fileManager: FileManager
    private let applicationsDirectory: String
    private let binaryDirectories: [String]

    /// Caches below this size are not worth an advisory.
    public static let minimumAdvisoryBytes: Int64 = 500_000_000
    /// A Safe/Developer cache untouched this long is a "nothing is using this" signal.
    public static let staleCacheDays = 60

    public init(
        fileManager: FileManager = .default,
        applicationsDirectory: String = "/Applications",
        binaryDirectories: [String] = ["/usr/local/bin", "/opt/homebrew/bin"]
    ) {
        self.fileManager = fileManager
        self.applicationsDirectory = applicationsDirectory
        self.binaryDirectories = binaryDirectories
    }

    public func advisories(for scan: FullScanResult, now: Date = Date()) -> [Advisory] {
        var found: [Advisory] = []
        let results = scan.levelResults.values.flatMap(\.targetResults)

        for result in results {
            if let orphan = orphanAdvisory(for: result) {
                found.append(orphan)
            } else if let stale = staleCacheAdvisory(for: result, now: now) {
                found.append(stale)
            }
        }
        return found.sorted { $0.bytes > $1.bytes }
    }

    // MARK: - Orphaned tool data

    /// Which targets belong to which uninstallable tool, and how to spot the tool.
    /// Only tools whose absence is cheap and unambiguous to detect are listed.
    private func orphanAdvisory(for result: TargetScanResult) -> Advisory? {
        guard result.totalBytes >= Self.minimumAdvisoryBytes else { return nil }

        let check: (tool: String, installed: Bool)?
        switch result.target.id {
        case "xcode-derived-data", "xcode-device-support", "core-simulator-caches", "xcode-archives":
            check = ("Xcode", appInstalled(named: "Xcode"))
        case "ollama-models":
            check = ("Ollama", appInstalled(named: "Ollama") || binaryInstalled(named: "ollama"))
        case "jetbrains-cache":
            check = ("a JetBrains IDE", jetBrainsInstalled())
        case "unity-cache":
            check = ("Unity", appInstalled(named: "Unity") || directoryExists("\(applicationsDirectory)/Unity"))
        default:
            check = nil
        }

        guard let check, !check.installed else { return nil }
        return Advisory(
            id: "orphan-\(result.target.id)",
            title: "\(result.target.displayName) left behind",
            detail: "\(check.tool) does not appear to be installed anymore, but "
                + "\(DiskSpaceMonitor.formatBytes(result.totalBytes)) of its data is still on disk.",
            targetID: result.target.id,
            bytes: result.totalBytes
        )
    }

    // MARK: - Untouched caches

    private func staleCacheAdvisory(for result: TargetScanResult, now: Date) -> Advisory? {
        guard result.totalBytes >= Self.minimumAdvisoryBytes else { return nil }
        // Only regenerating caches: age says nothing about installers or archives.
        guard result.target.regenerates else { return nil }

        let dates = result.resolvedPaths.compactMap(\.lastModified)
        guard !dates.isEmpty, var newest = dates.max() else { return nil }

        let shallowDays = now.timeIntervalSince(newest) / 86400
        guard shallowDays >= Double(Self.staleCacheDays) else { return nil }

        // The shallow stat only sees direct-child changes; a cache can churn deep
        // inside without bumping its root. Verify with a bounded walk before
        // claiming anything is untouched. A recent file anywhere kills the advisory.
        for resolved in result.resolvedPaths {
            if let deepNewest = newestModification(under: resolved.path), deepNewest > newest {
                newest = deepNewest
            }
        }
        let days = Int(now.timeIntervalSince(newest) / 86400)
        guard days >= Self.staleCacheDays else { return nil }

        return Advisory(
            id: "stale-\(result.target.id)",
            title: "\(result.target.displayName) untouched for \(days) days",
            detail: "Nothing has written to this cache since "
                + "\(Self.dayFormatter.string(from: newest)). "
                + "\(DiskSpaceMonitor.formatBytes(result.totalBytes)) would regenerate only if something needs it.",
            targetID: result.target.id,
            bytes: result.totalBytes
        )
    }

    /// Newest content-modification date in a tree, sampling at most `limit` entries.
    /// The cap keeps advisories cheap on huge caches. A truncated walk can miss a
    /// recent file and let a false "untouched" through; that is an accepted trade:
    /// an advisory is a pointer, it never selects or deletes anything.
    private func newestModification(under path: String, limit: Int = 1500) -> Date? {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsPackageDescendants]
        ) else { return nil }

        var newest: Date?
        var visited = 0
        for case let item as URL in enumerator {
            visited += 1
            if visited > limit { break }
            if let date = try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                if newest.map({ date > $0 }) ?? true { newest = date }
            }
        }
        return newest
    }

    // MARK: - Installed-tool checks

    private func appInstalled(named name: String) -> Bool {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: applicationsDirectory) else { return false }
        return entries.contains { $0.hasPrefix(name) && $0.hasSuffix(".app") }
    }

    private func binaryInstalled(named name: String) -> Bool {
        binaryDirectories.contains { fileManager.fileExists(atPath: "\($0)/\(name)") }
    }

    private func directoryExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func jetBrainsInstalled() -> Bool {
        let ideNames = [
            "IntelliJ", "PyCharm", "WebStorm", "PhpStorm", "CLion", "GoLand",
            "Rider", "RubyMine", "DataGrip", "AppCode", "Android Studio", "Fleet"
        ]
        guard let entries = try? fileManager.contentsOfDirectory(atPath: applicationsDirectory) else { return false }
        return entries.contains { entry in
            entry.hasSuffix(".app") && ideNames.contains { entry.hasPrefix($0) }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
