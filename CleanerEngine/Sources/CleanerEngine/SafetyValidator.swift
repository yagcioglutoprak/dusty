import Foundation
import Darwin

public enum SafetyError: Error, Equatable, Sendable {
    case pathNotInAllowlist(String)
    case prohibitedPath(String)
    case symlinkRefusal(String)
    case outsideBootVolume(String)
    case pathTraversal(String)
    case invalidPath(String)
}

/// Enforces the allowlist model and safety rules. All deletion paths must pass validation here.
public struct SafetyValidator: Sendable {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let bootVolumeURL: URL
    private let allowedTargetIDs: Set<String>

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        bootVolumeURL: URL? = nil,
        allowedTargets: [CleanupTarget] = CleanupTargetRegistry.all
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        // Use the data volume containing the home directory (not the read-only system volume at "/").
        self.bootVolumeURL = bootVolumeURL ?? self.homeDirectory
        self.allowedTargetIDs = Set(allowedTargets.map(\.id))
    }

    /// Paths that must NEVER be touched, even as prefixes.
    public static let prohibitedPrefixes: [String] = [
        "Documents",
        "Desktop",
        "Pictures",
        "Photos Library.photoslibrary",
        "Music",
        "Movies",
        "Mail",
        "Mobile Documents", // iCloud Drive
        "Keychains",
    ]

    /// Application Support is blocked unless the path is an explicit allowlisted browser cache subpath.
    private static let allowedApplicationSupportSuffixes: [String] = [
        "/Google/Chrome/Default/Service Worker/CacheStorage",
    ]

    public func expandPath(_ template: String) -> String {
        if template.hasPrefix("~/") {
            return (homeDirectory.path as NSString).appendingPathComponent(String(template.dropFirst(2)))
        }
        if template == "~" {
            return homeDirectory.path
        }
        return template
    }

    public func resolveAllowlistedPaths(for target: CleanupTarget) -> [String] {
        guard allowedTargetIDs.contains(target.id) else { return [] }

        if target.usesDynamicPaths {
            return resolveDynamicPaths(for: target)
        }

        return target.pathTemplates.map { expandPath($0) }
    }

    public func validateDeletionPath(_ path: String, for target: CleanupTarget) -> Result<Void, SafetyError> {
        guard allowedTargetIDs.contains(target.id) else {
            return .failure(.pathNotInAllowlist(path))
        }

        if containsPathTraversal(path) {
            return .failure(.pathTraversal(path))
        }

        let standardized = (path as NSString).standardizingPath
        guard !standardized.isEmpty else {
            return .failure(.invalidPath(path))
        }

        if containsPathTraversal(standardized) {
            return .failure(.pathTraversal(standardized))
        }

        let url = URL(fileURLWithPath: standardized, isDirectory: true)

        if isSymlink(at: url) {
            return .failure(.symlinkRefusal(standardized))
        }

        if matchesProhibitedPath(standardized) {
            return .failure(.prohibitedPath(standardized))
        }

        let allowlistedRoots = resolveAllowlistedPaths(for: target)
        guard isPath(standardized, underAnyOf: allowlistedRoots, for: target) else {
            return .failure(.pathNotInAllowlist(standardized))
        }

        if !isOnBootVolume(url) {
            return .failure(.outsideBootVolume(standardized))
        }

        return .success(())
    }

    public func isPathAllowlisted(_ path: String, for target: CleanupTarget) -> Bool {
        validateDeletionPath(path, for: target).error == nil
    }

    // MARK: - Private

    private func isSymlink(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else {
            return false
        }
        return values.isSymbolicLink == true
    }

    private func containsPathTraversal(_ path: String) -> Bool {
        path.split(separator: "/").contains(where: { $0 == ".." })
    }

    public func isOnBootVolume(_ url: URL) -> Bool {
        guard let pathMount = Self.volumeMountPoint(for: url.path),
              let bootMount = Self.volumeMountPoint(for: bootVolumeURL.path) else {
            return url.path.hasPrefix(bootVolumeURL.path)
        }
        return pathMount == bootMount
    }

    private static func volumeMountPoint(for path: String) -> String? {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return nil }
        return withUnsafePointer(to: stats.f_mntonname) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }
    }

    private static func volumeID(for path: String) -> fsid_t? {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return nil }
        return stats.f_fsid
    }

    private static func volumeIDsMatch(_ a: fsid_t, _ b: fsid_t) -> Bool {
        withUnsafeBytes(of: a) { aBytes in
            withUnsafeBytes(of: b) { bBytes in
                aBytes.elementsEqual(bBytes)
            }
        }
    }

    private func matchesProhibitedPath(_ path: String) -> Bool {
        let homePath = homeDirectory.path
        for prohibited in Self.prohibitedPrefixes {
            let blocked = (homePath as NSString).appendingPathComponent(prohibited)
            if path == blocked || path.hasPrefix(blocked + "/") {
                return true
            }
        }

        let appSupport = (homePath as NSString).appendingPathComponent("Library/Application Support")
        if path == appSupport || path.hasPrefix(appSupport + "/") {
            let allowed = Self.allowedApplicationSupportSuffixes.contains { suffix in
                path.hasSuffix(suffix) || path.contains(suffix + "/")
            }
            if !allowed {
                return true
            }
        }

        let keychainPath = (homePath as NSString).appendingPathComponent("Library/Keychains")
        if path == keychainPath || path.hasPrefix(keychainPath + "/") {
            return true
        }

        return false
    }

    private func isPath(_ path: String, underAnyOf roots: [String], for target: CleanupTarget) -> Bool {
        for root in roots {
            let standardizedRoot = (root as NSString).standardizingPath
            if path == standardizedRoot || path.hasPrefix(standardizedRoot + "/") {
                return true
            }
        }
        return false
    }

    private func resolveDynamicPaths(for target: CleanupTarget) -> [String] {
        switch target.id {
        case "xcode-device-support":
            return oldDeviceSupportPaths()
        case "simulator-unavailable":
            return ["simctl:unavailable"]
        case "docker-prune":
            return dockerInstalled() ? ["docker:system-prune"] : []
        case "downloads-installers":
            return installerPathsInDownloads()
        case "old-simulators":
            return unusedSimulatorDevicePaths()
        default:
            return target.pathTemplates.map { expandPath($0) }
        }
    }

    private func oldDeviceSupportPaths() -> [String] {
        let base = expandPath("~/Library/Developer/Xcode/iOS DeviceSupport")
        guard let contents = try? fileManager.contentsOfDirectory(atPath: base) else { return [] }
        let sorted = contents.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
        guard sorted.count > 1 else { return [] }
        return sorted.dropFirst().map { (base as NSString).appendingPathComponent($0) }
    }

    private func installerPathsInDownloads() -> [String] {
        let downloads = expandPath("~/Downloads")
        guard let contents = try? fileManager.contentsOfDirectory(atPath: downloads) else { return [] }
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        return contents.compactMap { name -> String? in
            let lower = name.lowercased()
            guard lower.hasSuffix(".dmg") || lower.hasSuffix(".pkg") else { return nil }
            let path = (downloads as NSString).appendingPathComponent(name)
            guard let modified = (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                  modified < cutoff else { return nil }
            return path
        }
    }

    private func unusedSimulatorDevicePaths() -> [String] {
        let base = expandPath("~/Library/Developer/CoreSimulator/Devices")
        return SimulatorHelper.unusedDevicePaths(basePath: base, fileManager: fileManager).map(\.path)
    }

    private func dockerInstalled() -> Bool {
        fileManager.fileExists(atPath: "/usr/local/bin/docker")
            || fileManager.fileExists(atPath: "/opt/homebrew/bin/docker")
    }
}

private extension Result where Success == Void, Failure == SafetyError {
    var error: SafetyError? {
        if case .failure(let e) = self { return e }
        return nil
    }
}
