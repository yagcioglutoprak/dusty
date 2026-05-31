import Foundation

public struct SizeCalculator: Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Calculates on-disk allocated size using `totalFileAllocatedSizeKey`.
    public func allocatedSize(at path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        if isSymlink(at: url) { return 0 }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }

        if isDirectory.boolValue {
            return directoryAllocatedSize(at: url)
        }
        return fileAllocatedSize(at: url)
    }

    public func directoryAllocatedSize(at url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let item as URL in enumerator {
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
