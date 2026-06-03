import Foundation

/// `@unchecked Sendable`: the only stored reference is `FileManager`, used purely for
/// delegate-free, concurrency-safe size queries, so sharing across tasks is safe.
public struct SizeCalculator: @unchecked Sendable {
    private let fileManager: FileManager
    private let cache: SizeCache?

    public init(fileManager: FileManager = .default, cache: SizeCache? = nil) {
        self.fileManager = fileManager
        self.cache = cache
    }

    /// Calculates on-disk allocated size using `totalFileAllocatedSizeKey`.
    ///
    /// With `.cached` and a cache attached, an unchanged directory is not re-walked.
    /// `.fresh` (the default) always re-walks, so callers that act on the number
    /// (interactive scan, delete) never see a stale value.
    public func allocatedSize(at path: String, policy: SizeCachePolicy = .fresh) -> Int64 {
        let url = URL(fileURLWithPath: path)
        if isSymlink(at: url) { return 0 }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }

        if isDirectory.boolValue {
            return cachedDirectorySize(at: url, policy: policy)
        }
        return fileAllocatedSize(at: url)
    }

    private func cachedDirectorySize(at url: URL, policy: SizeCachePolicy) -> Int64 {
        guard policy == .cached, let cache else {
            return directoryAllocatedSize(at: url)
        }
        let mtime = directoryMtime(at: url)
        if let hit = cache.validSize(for: url.path, currentMtime: mtime) {
            return hit
        }
        let size = directoryAllocatedSize(at: url)
        // Never cache a partial total left by a cancelled walk.
        if !Task.isCancelled {
            cache.record(size, for: url.path, mtime: mtime)
        }
        return size
    }

    private func directoryMtime(at url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    public func directoryAllocatedSize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            // Bail out of a large walk promptly when the owning scan task is cancelled.
            if Task.isCancelled { break }
            if isSymlink(at: item) {
                enumerator.skipDescendants()
                continue
            }
            total += fileAllocatedSize(at: item)
        }
        return total
    }

    private func fileAllocatedSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
              let size = values.totalFileAllocatedSize else { return 0 }
        return Int64(size)
    }

    private func isSymlink(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}
