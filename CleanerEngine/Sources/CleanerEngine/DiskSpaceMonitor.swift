import Foundation

public struct DiskSpaceMonitor: Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func freeSpaceBytes(on volumeURL: URL? = nil) -> Int64 {
        let url = volumeURL ?? fileManager.homeDirectoryForCurrentUser
        guard let attrs = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = attrs.volumeAvailableCapacityForImportantUsage else {
            return legacyFreeSpace(at: url.path)
        }
        return capacity
    }

    /// Literal free space (excludes purgeable). Best for measuring a deletion delta.
    public func availableCapacityBytes(on volumeURL: URL? = nil) -> Int64 {
        let url = volumeURL ?? fileManager.homeDirectoryForCurrentUser
        if let attrs = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let capacity = attrs.volumeAvailableCapacity {
            return Int64(capacity)
        }
        return legacyFreeSpace(at: url.path)
    }

    public func totalSpaceBytes(on volumeURL: URL? = nil) -> Int64 {
        let url = volumeURL ?? fileManager.homeDirectoryForCurrentUser
        guard let attrs = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey]),
              let total = attrs.volumeTotalCapacity else { return 0 }
        return Int64(total)
    }

    private func legacyFreeSpace(at path: String) -> Int64 {
        guard let attrs = try? fileManager.attributesOfFileSystem(forPath: path),
              let free = attrs[.systemFreeSize] as? NSNumber else { return 0 }
        return free.int64Value
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    public static func formatFreeSpaceCompact(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1 {
            return String(format: "%.0f GB free", gb)
        }
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.0f MB free", mb)
    }
}
