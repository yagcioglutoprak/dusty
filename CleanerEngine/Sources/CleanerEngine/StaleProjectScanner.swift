import Foundation

/// A regenerable build artifact inside a project nobody has touched for a while:
/// a node_modules three renames ago, a Cargo target dir from an abandoned
/// experiment. These hide gigabytes precisely because they sit outside every
/// cache directory a cleaner normally looks at.
public struct StaleProjectArtifact: Codable, Sendable, Hashable {
    /// The artifact directory itself (the thing that would be deleted).
    public let path: String
    /// Project folder name, for display ("my-app").
    public let projectName: String
    /// The artifact directory's name ("node_modules", "target", ".venv").
    public let artifactName: String
    /// Newest write anywhere in the project outside its artifacts.
    public let lastActivity: Date

    public init(path: String, projectName: String, artifactName: String, lastActivity: Date) {
        self.path = path
        self.projectName = projectName
        self.artifactName = artifactName
        self.lastActivity = lastActivity
    }
}

/// Finds regenerable build artifacts in projects that have not been touched for
/// `thresholdDays`. Detection is marker-based and deliberately narrow: an artifact
/// directory only counts when the project's manifest sits right next to it, so a
/// user folder that happens to be called "target" or "build" is never offered.
///
/// Documents and Desktop are not scanned: they are prohibited paths for the whole
/// engine, and that stays absolute.
public enum StaleProjectScanner {
    /// Where projects usually live. All of these are optional; missing roots are
    /// skipped silently.
    public static let scanRootTemplates = [
        "~/Developer", "~/Projects", "~/projects", "~/Code", "~/code",
        "~/dev", "~/src", "~/repos", "~/git", "~/work", "~/workspace", "~/Sites"
    ]

    /// A project counts as stale when nothing in it (outside artifacts) was
    /// written for this long.
    public static let defaultThresholdDays = 30

    /// How deep below a scan root project folders are looked for
    /// (root/client/project = 3). Projects are never nested inside projects.
    private static let maxDiscoveryDepth = 3

    /// Manifest file → the sibling artifact directories it regenerates.
    /// Only unambiguous, tool-owned directory names are listed. "dist" and
    /// "vendor" are deliberately absent: both can hold hand-written or
    /// hand-patched code.
    private static let artifactsByMarker: [String: [String]] = [
        "package.json": ["node_modules", ".next", ".nuxt", ".turbo"],
        "Cargo.toml": ["target"],
        "pyproject.toml": [".venv", "venv"],
        "requirements.txt": [".venv", "venv"],
        "setup.py": [".venv", "venv"],
        "Podfile": ["Pods"],
        "pubspec.yaml": ["build", ".dart_tool"],
        "build.gradle": ["build", ".gradle"],
        "build.gradle.kts": ["build", ".gradle"],
    ]

    private static let allArtifactNames: Set<String> = Set(artifactsByMarker.values.flatMap { $0 })

    public static func staleArtifacts(
        scanRoots: [String],
        fileManager: FileManager = .default,
        now: Date = Date(),
        thresholdDays: Int = defaultThresholdDays
    ) -> [StaleProjectArtifact] {
        let cutoff = now.addingTimeInterval(-Double(thresholdDays) * 86400)
        var artifacts: [StaleProjectArtifact] = []
        for root in scanRoots {
            collectProjects(under: root, depth: 0, fileManager: fileManager, cutoff: cutoff, into: &artifacts)
        }
        return artifacts.sorted { $0.path < $1.path }
    }

    private static func collectProjects(
        under path: String,
        depth: Int,
        fileManager: FileManager,
        cutoff: Date,
        into artifacts: inout [StaleProjectArtifact]
    ) {
        if Task.isCancelled { return }
        guard depth <= maxDiscoveryDepth else { return }
        guard let entries = try? fileManager.contentsOfDirectory(atPath: path) else { return }
        let entrySet = Set(entries)

        let markers = artifactsByMarker.keys.filter { entrySet.contains($0) }
        if !markers.isEmpty {
            appendArtifacts(projectPath: path, entries: entrySet, markers: markers,
                            fileManager: fileManager, cutoff: cutoff, into: &artifacts)
            return // a project is a leaf; nested projects are its own business
        }

        for entry in entries where !entry.hasPrefix(".") {
            if Task.isCancelled { return }
            let childPath = (path as NSString).appendingPathComponent(entry)
            guard isRealDirectory(childPath, fileManager: fileManager) else { continue }
            collectProjects(under: childPath, depth: depth + 1,
                            fileManager: fileManager, cutoff: cutoff, into: &artifacts)
        }
    }

    private static func appendArtifacts(
        projectPath: String,
        entries: Set<String>,
        markers: [String],
        fileManager: FileManager,
        cutoff: Date,
        into artifacts: inout [StaleProjectArtifact]
    ) {
        let candidateNames = Set(markers.flatMap { artifactsByMarker[$0] ?? [] })
        let present = candidateNames.filter { entries.contains($0) }
        guard !present.isEmpty else { return }

        guard let lastActivity = newestProjectWrite(at: projectPath, fileManager: fileManager),
              lastActivity < cutoff else { return }

        let projectName = (projectPath as NSString).lastPathComponent
        for name in present.sorted() {
            let artifactPath = (projectPath as NSString).appendingPathComponent(name)
            guard isRealDirectory(artifactPath, fileManager: fileManager) else { continue }
            artifacts.append(StaleProjectArtifact(
                path: artifactPath,
                projectName: projectName,
                artifactName: name,
                lastActivity: lastActivity
            ))
        }
    }

    /// Newest write in the project, ignoring the artifact directories themselves
    /// (a package manager touching node_modules is not "working on the project").
    /// Walks at most two levels: sources live shallow, and a full-tree walk over
    /// every project would make the scan crawl. `.git` is included on purpose:
    /// its index mtime moves with every commit, checkout, and stage, which is the
    /// single best "someone is working here" signal.
    static func newestProjectWrite(at projectPath: String, fileManager: FileManager) -> Date? {
        var newest: Date?
        func consider(_ path: String) {
            guard let date = (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            else { return }
            if newest.map({ date > $0 }) ?? true { newest = date }
        }

        consider(projectPath)
        consider((projectPath as NSString).appendingPathComponent(".git/index"))

        guard let entries = try? fileManager.contentsOfDirectory(atPath: projectPath) else { return newest }
        for entry in entries where !allArtifactNames.contains(entry) && entry != ".git" {
            let entryPath = (projectPath as NSString).appendingPathComponent(entry)
            consider(entryPath)
            if isRealDirectory(entryPath, fileManager: fileManager),
               let children = try? fileManager.contentsOfDirectory(atPath: entryPath) {
                for child in children {
                    consider((entryPath as NSString).appendingPathComponent(child))
                }
            }
        }
        return newest
    }

    /// True for an actual directory, never a symlink to one: a symlinked artifact
    /// could point anywhere, so it is not offered (the validator would refuse it
    /// at delete time anyway; this keeps it out of the list entirely).
    private static func isRealDirectory(_ path: String, fileManager: FileManager) -> Bool {
        let url = URL(fileURLWithPath: path)
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { return false }
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
