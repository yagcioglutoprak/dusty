import Foundation

/// One process's share of memory, as sampled from the kernel.
public struct ProcessMemorySample: Sendable, Hashable {
    public let pid: Int32
    /// The process macOS holds responsible for this one: the app behind a helper,
    /// a web content process, or a tool started from Terminal. Equal to `pid`
    /// when the process answers for itself or the kernel would not say.
    public let responsiblePID: Int32
    public let executablePath: String
    /// Physical footprint: the figure Activity Monitor's Memory column shows.
    public let footprintBytes: Int64

    public init(pid: Int32, responsiblePID: Int32, executablePath: String, footprintBytes: Int64) {
        self.pid = pid
        self.responsiblePID = responsiblePID
        self.executablePath = executablePath
        self.footprintBytes = footprintBytes
    }
}

/// Memory held by one app and every process working for it, or by one
/// stand-alone process that belongs to no app.
///
/// A browser is dozens of processes (renderers, GPU, network, extensions), and
/// Safari's pages run in WebKit processes that live outside Safari.app entirely.
/// Listing them one by one, the way Activity Monitor does, hides what quitting
/// the app would actually give back. Grouping by responsible app shows it.
public struct AppMemoryUsage: Sendable, Hashable, Identifiable {
    /// The app's bundle path, or the executable path of a stand-alone process.
    public let id: String
    public let name: String
    /// Nil for processes that are not part of an app.
    public let bundlePath: String?
    /// The app's own process (its main executable), or the group's first process.
    public let leaderPID: Int32
    /// Every process in the group, ascending.
    public let pids: [Int32]
    public let footprintBytes: Int64

    public init(id: String, name: String, bundlePath: String?, leaderPID: Int32, pids: [Int32], footprintBytes: Int64) {
        self.id = id
        self.name = name
        self.bundlePath = bundlePath
        self.leaderPID = leaderPID
        self.pids = pids
        self.footprintBytes = footprintBytes
    }

    public var processCount: Int { pids.count }
    public var isApp: Bool { bundlePath != nil }
}

/// Pure grouping of process samples into per-app totals. No kernel calls, so
/// the attribution rules are covered by unit tests.
public enum AppMemoryGrouping {
    /// Groups samples by the app responsible for them, largest first.
    ///
    /// A process belongs to the app bundle its responsible process runs from
    /// (one hop is enough: macOS already resolves the chain), otherwise to the
    /// bundle it runs from itself. Helpers nested inside an app's frameworks
    /// count toward the outermost app. Anything else stands alone, keyed by its
    /// executable, so ten `node` servers read as one line rather than ten.
    ///
    /// `appPIDs` are the processes macOS runs as apps of their own (Dock and
    /// menu bar apps). Each keeps its own line even when its bundle sits inside
    /// another app's, the way Simulator lives inside Xcode or a login-item
    /// helper inside its app, so quitting one never claims the other's memory.
    public static func group(
        _ samples: [ProcessMemorySample],
        appPIDs: Set<Int32> = [],
        excludingPIDs excluded: Set<Int32> = []
    ) -> [AppMemoryUsage] {
        let kept = samples.filter { !excluded.contains($0.pid) && $0.footprintBytes > 0 }
        var byPID: [Int32: ProcessMemorySample] = [:]
        for sample in kept { byPID[sample.pid] = sample }

        struct Bucket {
            var pids: [Int32] = []
            var bytes: Int64 = 0
            var bundlePath: String?
            var executablePath: String
        }
        var buckets: [String: Bucket] = [:]

        for sample in kept {
            let owner: ProcessMemorySample
            if appPIDs.contains(sample.pid) {
                owner = sample
            } else if sample.responsiblePID != sample.pid, let responsible = byPID[sample.responsiblePID] {
                owner = responsible
            } else {
                owner = sample
            }
            let bundle = appPIDs.contains(owner.pid)
                ? (innermostAppBundlePath(forExecutable: owner.executablePath)
                    ?? appBundlePath(forExecutable: owner.executablePath))
                : appBundlePath(forExecutable: owner.executablePath)
            let key = bundle ?? owner.executablePath
            var bucket = buckets[key] ?? Bucket(bundlePath: bundle, executablePath: owner.executablePath)
            bucket.pids.append(sample.pid)
            let (total, overflow) = bucket.bytes.addingReportingOverflow(sample.footprintBytes)
            bucket.bytes = overflow ? .max : total
            buckets[key] = bucket
        }

        return buckets.map { key, bucket in
            let pids = bucket.pids.sorted()
            let leader: Int32
            if let bundle = bucket.bundlePath {
                // The main executable sits directly in the bundle; helpers sit in
                // nested bundles. A registered app wins, then the lowest pid (the
                // one launched first).
                let mains = pids.filter { pid in
                    guard let path = byPID[pid]?.executablePath else { return false }
                    return isMainExecutable(path, of: bundle)
                }
                leader = mains.first { appPIDs.contains($0) } ?? mains.first ?? pids[0]
            } else {
                leader = pids[0]
            }
            return AppMemoryUsage(
                id: key,
                name: displayName(bundlePath: bucket.bundlePath, executablePath: bucket.executablePath),
                bundlePath: bucket.bundlePath,
                leaderPID: leader,
                pids: pids,
                footprintBytes: bucket.bytes
            )
        }
        .sorted { lhs, rhs in
            lhs.footprintBytes != rhs.footprintBytes ? lhs.footprintBytes > rhs.footprintBytes : lhs.id < rhs.id
        }
    }

    /// The outermost `.app` bundle an executable lives in, or nil.
    /// "/Applications/Google Chrome.app/Contents/Frameworks/…/Helper.app/Contents/MacOS/Helper"
    /// belongs to "/Applications/Google Chrome.app".
    public static func appBundlePath(forExecutable path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        // The bundle has to be a folder on the way to the executable, never the
        // executable's own name.
        for index in components.indices.dropLast() {
            let component = components[index]
            if component.count > 4 && component.hasSuffix(".app") {
                return components[...index].joined(separator: "/")
            }
        }
        return nil
    }

    /// The innermost `.app` bundle an executable lives in: its own bundle, even
    /// when that bundle is nested inside another app's.
    public static func innermostAppBundlePath(forExecutable path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        for index in components.indices.dropLast().reversed() {
            let component = components[index]
            if component.count > 4 && component.hasSuffix(".app") {
                return components[...index].joined(separator: "/")
            }
        }
        return nil
    }

    /// True when `path` is the bundle's own executable rather than a helper
    /// nested somewhere inside it.
    static func isMainExecutable(_ path: String, of bundle: String) -> Bool {
        guard path.hasPrefix(bundle + "/") else { return false }
        let inside = path.dropFirst(bundle.count + 1)
        return !inside.contains(".app/")
    }

    /// "Google Chrome" for a bundle, "node" for a bare executable.
    static func displayName(bundlePath: String?, executablePath: String) -> String {
        if let bundlePath {
            let name = (bundlePath as NSString).lastPathComponent
            return String(name.dropLast(4))
        }
        return (executablePath as NSString).lastPathComponent
    }
}
