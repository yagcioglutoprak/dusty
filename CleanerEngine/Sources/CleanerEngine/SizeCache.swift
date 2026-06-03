import Foundation

/// Whether a size lookup may use the cache or must re-walk the directory.
public enum SizeCachePolicy: Sendable {
    /// Always re-walk. Used by the interactive scan and the delete path, where the
    /// number is acted on and must be current.
    case fresh
    /// Reuse a cached size while it is still valid. Used by background scans.
    case cached
}

/// Thread-safe cache of directory allocated sizes, keyed on path.
///
/// A cached entry is valid for a `.cached` read only while the directory's
/// modification date is unchanged AND the entry is younger than `ttl`. The TTL
/// backstop matters because a directory's mtime does not change when a deeply
/// nested file grows, so mtime alone can be stale.
///
/// `@unchecked Sendable`: all mutable state is guarded by `lock`.
public final class SizeCache: @unchecked Sendable {
    private struct Entry {
        let size: Int64
        let mtime: Date
        let recordedAt: Date
    }

    private var store: [String: Entry] = [:]
    private let lock = NSLock()
    private let ttl: TimeInterval
    private let now: () -> Date

    public init(ttl: TimeInterval = 3600, now: @escaping () -> Date = Date.init) {
        self.ttl = ttl
        self.now = now
    }

    /// The cached size, if an entry exists, its mtime matches, and it is within the TTL.
    func validSize(for path: String, currentMtime: Date?) -> Int64? {
        guard let currentMtime else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard let entry = store[path],
              entry.mtime == currentMtime,
              now().timeIntervalSince(entry.recordedAt) < ttl else { return nil }
        return entry.size
    }

    func record(_ size: Int64, for path: String, mtime: Date?) {
        guard let mtime else { return }
        lock.lock(); defer { lock.unlock() }
        store[path] = Entry(size: size, mtime: mtime, recordedAt: now())
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        store.removeAll()
    }
}
