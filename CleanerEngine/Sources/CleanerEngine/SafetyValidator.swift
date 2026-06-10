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
///
/// `@unchecked Sendable`: all stored state is immutable (`let`); the only reference type is
/// `FileManager`, used for delegate-free, concurrency-safe queries, so it is safe to share.
public struct SafetyValidator: @unchecked Sendable {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let bootVolumeURL: URL
    private let allowedTargetIDs: Set<String>
    private let allowedApplicationSupportSuffixes: [String]

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
        self.allowedApplicationSupportSuffixes = Self.applicationSupportSuffixes(from: allowedTargets)
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

    /// Application Support is blocked unless the path is one of the explicit, named
    /// cache subfolders an allowed target declares. The exemptions are derived from the
    /// targets' own path templates, so registering a new app cache target is a single
    /// registry edit and the validator can never drift out of sync with it. Each
    /// template names a specific cache directory, never an app's whole Application
    /// Support folder, so real data (workspaces, settings, databases) stays protected.
    /// The allowlist-root containment check below is the real gate; this list only
    /// decides what is NOT prohibited.
    private static func applicationSupportSuffixes(from targets: [CleanupTarget]) -> [String] {
        let prefix = "~/Library/Application Support"
        var suffixes: [String] = []
        for target in targets {
            for template in target.pathTemplates where template.hasPrefix(prefix + "/") {
                let suffix = String(template.dropFirst(prefix.count))
                if suffix.count > 1 { suffixes.append(suffix) }
            }
        }
        return suffixes
    }

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
        validateDeletionPath(path, for: target, allowlistedRoots: resolveAllowlistedPaths(for: target))
    }

    /// Validate a single path with the target's allowlist roots supplied by the caller.
    /// Lets a batch delete resolve dynamic roots (e.g. `simctl list`, Downloads scan) once
    /// instead of re-resolving for every path.
    public func validateDeletionPath(
        _ path: String,
        for target: CleanupTarget,
        allowlistedRoots: [String]
    ) -> Result<Void, SafetyError> {
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

        guard isPath(standardized, underAnyOf: allowlistedRoots, for: target) else {
            return .failure(.pathNotInAllowlist(standardized))
        }

        // Defense in depth against ANCESTOR symlinks. `standardizingPath` does not resolve
        // symlinks, and the leaf check above only inspects the final component, so a symlinked
        // directory anywhere above the leaf (e.g. a relocated `~/Library/Caches`) could otherwise
        // redirect a delete outside the allowlist. Resolve symlinks on both sides and require the
        // resolved candidate to still live inside a resolved allowlist root.
        guard isPath(standardized, underAnyOfResolvingSymlinks: allowlistedRoots) else {
            return .failure(.symlinkRefusal(standardized))
        }

        if !isOnBootVolume(url) {
            return .failure(.outsideBootVolume(standardized))
        }

        return .success(())
    }

    public func isPathAllowlisted(_ path: String, for target: CleanupTarget) -> Bool {
        validateDeletionPath(path, for: target).error == nil
    }

    /// Validate where a restore is allowed to put a file back. Runs the same pipeline as
    /// deletion validation (traversal, prohibited paths, containment, ancestor symlinks),
    /// but against the target's *static* roots: dynamic targets re-resolve their paths by
    /// scanning the disk, and a just-deleted item is no longer there to be found, so the
    /// resolved list can never contain a restore destination.
    public func validateRestoreDestination(_ path: String, for target: CleanupTarget) -> Result<Void, SafetyError> {
        validateDeletionPath(path, for: target, allowlistedRoots: restoreRoots(for: target))
    }

    /// Static directories a target's deleted items may be restored into. Mirrors
    /// `resolveDynamicPaths`: each dynamic target maps to the fixed base directory its
    /// scan enumerates. Targets with no filesystem paths (simctl, docker) return nothing,
    /// because there is nothing of theirs a restore could legitimately recreate.
    public func restoreRoots(for target: CleanupTarget) -> [String] {
        guard allowedTargetIDs.contains(target.id) else { return [] }
        guard target.usesDynamicPaths else {
            return target.pathTemplates.map { expandPath($0) }
        }
        switch target.id {
        case "xcode-device-support":
            return [expandPath("~/Library/Developer/Xcode/iOS DeviceSupport")]
        case "xcode-archives":
            return [expandPath("~/Library/Developer/Xcode/Archives")]
        case "downloads-installers":
            return [expandPath("~/Downloads")]
        case "old-simulators":
            return [expandPath("~/Library/Developer/CoreSimulator/Devices")]
        case "telegram-media-cache":
            return [
                expandPath("~/Library/Application Support/Telegram Desktop/tdata/user_data/cache"),
                expandPath("~/Library/Application Support/Telegram Desktop/tdata/user_data/media_cache"),
                expandPath("~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram")
            ]
        default:
            return []
        }
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
            let allowed = allowedApplicationSupportSuffixes.contains { suffix in
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

    /// Containment check after fully resolving symlinks on both the candidate and each root,
    /// so an ancestor symlink cannot smuggle a path outside its allowlist root.
    private func isPath(_ path: String, underAnyOfResolvingSymlinks roots: [String]) -> Bool {
        let realCandidate = realPath(path)
        for root in roots {
            let realRoot = realPath((root as NSString).standardizingPath)
            if realCandidate == realRoot || realCandidate.hasPrefix(realRoot + "/") {
                return true
            }
        }
        return false
    }

    /// Resolve symlinks in a path. Falls back to the input if resolution yields an empty string.
    private func realPath(_ path: String) -> String {
        let resolved = (path as NSString).resolvingSymlinksInPath
        return resolved.isEmpty ? path : resolved
    }

    private func resolveDynamicPaths(for target: CleanupTarget) -> [String] {
        switch target.id {
        case "xcode-device-support":
            return oldDeviceSupportPaths()
        case "xcode-archives":
            return archivePaths()
        case "simulator-unavailable":
            return ["simctl:unavailable"]
        case "docker-prune":
            return dockerInstalled() ? ["docker:system-prune"] : []
        case "downloads-installers":
            return installerPathsInDownloads()
        case "old-simulators":
            return unusedSimulatorDevicePaths()
        case "telegram-media-cache":
            return telegramMediaCachePaths()
        default:
            return target.pathTemplates.map { expandPath($0) }
        }
    }

    /// Telegram's re-downloadable media caches, and nothing else of Telegram's.
    /// The telegram.org build uses two fixed cache dirs under tdata; the App Store
    /// build keeps one media cache per signed-in account inside its group container.
    /// Chat databases (`postbox/db`) and settings are never resolved.
    private func telegramMediaCachePaths() -> [String] {
        var paths: [String] = []
        for template in [
            "~/Library/Application Support/Telegram Desktop/tdata/user_data/cache",
            "~/Library/Application Support/Telegram Desktop/tdata/user_data/media_cache"
        ] {
            let path = expandPath(template)
            if fileManager.fileExists(atPath: path) { paths.append(path) }
        }
        let group = expandPath("~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram")
        for base in [group, (group as NSString).appendingPathComponent("appstore")] {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: base) else { continue }
            for entry in entries where entry.hasPrefix("account-") {
                let media = (base as NSString).appendingPathComponent("\(entry)/postbox/media")
                if fileManager.fileExists(atPath: media) { paths.append(media) }
            }
        }
        return paths
    }

    /// Individual `.xcarchive` bundles under `~/Library/Developer/Xcode/Archives/<date>/`.
    private func archivePaths() -> [String] {
        let base = expandPath("~/Library/Developer/Xcode/Archives")
        guard let dateDirs = try? fileManager.contentsOfDirectory(atPath: base) else { return [] }
        var archives: [String] = []
        for dateDir in dateDirs {
            let dayPath = (base as NSString).appendingPathComponent(dateDir)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dayPath, isDirectory: &isDir), isDir.boolValue,
                  let entries = try? fileManager.contentsOfDirectory(atPath: dayPath) else { continue }
            for entry in entries where entry.hasSuffix(".xcarchive") {
                archives.append((dayPath as NSString).appendingPathComponent(entry))
            }
        }
        return archives
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
