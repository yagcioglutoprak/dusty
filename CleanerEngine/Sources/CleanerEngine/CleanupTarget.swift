import Foundation

/// How a target's selected items are removed. Modeled as a closed set rather than
/// magic strings so the scan and delete phases can never drift out of sync: a target
/// declares its action once, and the engine dispatches on the enum.
public enum CleanupAction: String, Codable, Sendable, Hashable {
    /// Ordinary filesystem deletion of validated paths (trash or permanent).
    case files
    /// `xcrun simctl delete unavailable` (no filesystem path).
    case simctlDeleteUnavailable
    /// `xcrun simctl delete <udid>`, where the UDID is the path's last component.
    case simctlDeleteDevice
    /// `docker system prune -af` (no filesystem path, no `--volumes`).
    case dockerPrune
    /// `tmutil deletelocalsnapshots <date>` for one Time Machine local snapshot
    /// (no filesystem path; the date token is the resolved path).
    case tmutilDeleteSnapshot

    /// True when the action is an external command with no real filesystem path,
    /// so path validation does not apply and must be skipped.
    public var isExternalCommand: Bool {
        switch self {
        case .files, .simctlDeleteDevice: return false
        case .simctlDeleteUnavailable, .dockerPrune, .tmutilDeleteSnapshot: return true
        }
    }
}

/// A data-driven cleanup target. Adding or removing a target is a one-line change in `CleanupTargetRegistry`.
public struct CleanupTarget: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let displayName: String
    public let level: CleanupLevel
    /// Path templates relative to home or absolute. `~` expands to the user home directory.
    public let pathTemplates: [String]
    public let category: String
    /// When true, delete directory contents but keep the directory itself.
    public let deletesContentsNotDirectory: Bool
    /// When true, the data regenerates automatically (safe tier).
    public let regenerates: Bool
    /// How selected items are removed. Defaults to ordinary file deletion.
    public let action: CleanupAction
    /// When true, items are ALWAYS permanently deleted, never moved to Trash, even
    /// when a Safe-undo clean would otherwise trash them. Required for "Empty Trash":
    /// trashing an item that already lives in the Trash is incoherent (it just shuffles
    /// the file within the Trash and reclaims nothing).
    public let bypassesTrash: Bool
    /// Bundle ID or app name hint shown in UI when the app should be quit first.
    public let requiresAppClosed: String?
    /// Precise bundle identifier for running-app detection (preferred over name).
    public let requiresAppBundleID: String?
    /// When true, paths are resolved dynamically (e.g. iOS DeviceSupport versions, Downloads .dmg).
    public let usesDynamicPaths: Bool
    /// When true, user must pick individual files (Level 3 checklist).
    public let requiresIndividualSelection: Bool
    /// For log targets: only include files older than N days (configured at scan time).
    public let respectsLogAgeThreshold: Bool
    /// When true, user must explicitly opt in (e.g. Docker prune).
    public let requiresExplicitOptIn: Bool

    public init(
        id: String,
        displayName: String,
        level: CleanupLevel,
        pathTemplates: [String],
        category: String,
        deletesContentsNotDirectory: Bool = false,
        regenerates: Bool = false,
        action: CleanupAction = .files,
        bypassesTrash: Bool = false,
        requiresAppClosed: String? = nil,
        requiresAppBundleID: String? = nil,
        usesDynamicPaths: Bool = false,
        requiresIndividualSelection: Bool = false,
        respectsLogAgeThreshold: Bool = false,
        requiresExplicitOptIn: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.level = level
        self.pathTemplates = pathTemplates
        self.category = category
        self.deletesContentsNotDirectory = deletesContentsNotDirectory
        self.regenerates = regenerates
        self.action = action
        self.bypassesTrash = bypassesTrash
        self.requiresAppClosed = requiresAppClosed
        self.requiresAppBundleID = requiresAppBundleID
        self.usesDynamicPaths = usesDynamicPaths
        self.requiresIndividualSelection = requiresIndividualSelection
        self.respectsLogAgeThreshold = respectsLogAgeThreshold
        self.requiresExplicitOptIn = requiresExplicitOptIn
    }

    public var needsUserSelection: Bool {
        requiresIndividualSelection || requiresExplicitOptIn
    }
}

public struct ResolvedPath: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let path: String
    public let displayName: String
    public let targetID: String
    public var estimatedBytes: Int64
    public var isSelected: Bool
    public var errorMessage: String?

    public init(
        id: String = UUID().uuidString,
        path: String,
        displayName: String,
        targetID: String,
        estimatedBytes: Int64 = 0,
        isSelected: Bool = true,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.targetID = targetID
        self.estimatedBytes = estimatedBytes
        self.isSelected = isSelected
        self.errorMessage = errorMessage
    }
}

public struct TargetScanResult: Identifiable, Codable, Sendable {
    public let id: String
    public let target: CleanupTarget
    public var resolvedPaths: [ResolvedPath]
    public var totalBytes: Int64
    public var scanErrors: [String]

    public init(target: CleanupTarget, resolvedPaths: [ResolvedPath], scanErrors: [String] = []) {
        self.id = target.id
        self.target = target
        self.resolvedPaths = resolvedPaths
        self.totalBytes = resolvedPaths.reduce(0) { $0 + $1.estimatedBytes }
        self.scanErrors = scanErrors
    }

    public var selectedBytes: Int64 {
        resolvedPaths.filter(\.isSelected).reduce(0) { $0 + $1.estimatedBytes }
    }

    public var selectedCount: Int {
        resolvedPaths.filter(\.isSelected).count
    }
}

public struct LevelScanResult: Codable, Sendable {
    public let level: CleanupLevel
    public var targetResults: [TargetScanResult]
    public var totalBytes: Int64

    public init(level: CleanupLevel, targetResults: [TargetScanResult]) {
        self.level = level
        self.targetResults = targetResults
        self.totalBytes = targetResults.reduce(0) { $0 + $1.totalBytes }
    }

    public var selectedBytes: Int64 {
        targetResults.reduce(0) { $0 + $1.selectedBytes }
    }

    public var selectedCount: Int {
        targetResults.reduce(0) { $0 + $1.selectedCount }
    }

    public var hasSelection: Bool { selectedCount > 0 }

    public var selectedPaths: [ResolvedPath] {
        targetResults.flatMap(\.resolvedPaths).filter(\.isSelected)
    }

    public var runningAppsToQuit: [String] {
        var apps = Set<String>()
        for result in targetResults {
            guard let app = result.target.requiresAppClosed else { continue }
            let hasSelected = result.resolvedPaths.contains(where: \.isSelected)
            if hasSelected { apps.insert(app) }
        }
        return apps.sorted()
    }

    public var hasPermissionErrors: Bool {
        targetResults.contains { result in
            result.scanErrors.contains { $0.localizedCaseInsensitiveContains("permission") || $0.contains("Operation not permitted") }
        }
    }
}

public struct FullScanResult: Codable, Sendable {
    public var levelResults: [CleanupLevel: LevelScanResult]
    public var scannedAt: Date
    public var totalBytes: Int64

    public init(levelResults: [CleanupLevel: LevelScanResult], scannedAt: Date = Date()) {
        self.levelResults = levelResults
        self.scannedAt = scannedAt
        self.totalBytes = levelResults.values.reduce(0) { $0 + $1.totalBytes }
    }
}

public struct DeletionEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let path: String
    public let bytes: Int64
    public let movedToTrash: Bool
    public let dryRun: Bool
    /// Where the item landed in Trash (for Undo / later purge).
    public let trashedPath: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        path: String,
        bytes: Int64,
        movedToTrash: Bool,
        dryRun: Bool,
        trashedPath: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.path = path
        self.bytes = bytes
        self.movedToTrash = movedToTrash
        self.dryRun = dryRun
        self.trashedPath = trashedPath
    }
}

public struct DeletionResult: Sendable {
    public let entries: [DeletionEntry]
    public let bytesFreed: Int64
    public let skippedPaths: [(path: String, reason: String)]
    public let freeSpaceBefore: Int64
    public let freeSpaceAfter: Int64

    public init(
        entries: [DeletionEntry],
        bytesFreed: Int64,
        skippedPaths: [(path: String, reason: String)],
        freeSpaceBefore: Int64,
        freeSpaceAfter: Int64
    ) {
        self.entries = entries
        self.bytesFreed = bytesFreed
        self.skippedPaths = skippedPaths
        self.freeSpaceBefore = freeSpaceBefore
        self.freeSpaceAfter = freeSpaceAfter
    }
}

public struct CleanerOptions: Sendable {
    public var dryRun: Bool
    public var moveToTrash: Bool
    public var logAgeThresholdDays: Int
    public var cleanupLevel: CleanupLevel?
    /// When set, Safe-level deletes go to Trash so they can be undone (then purged).
    public var trashSafeForUndo: Bool

    public init(
        dryRun: Bool = false,
        moveToTrash: Bool = false,
        logAgeThresholdDays: Int = 30,
        cleanupLevel: CleanupLevel? = nil,
        trashSafeForUndo: Bool = false
    ) {
        self.dryRun = dryRun
        self.moveToTrash = moveToTrash
        self.logAgeThresholdDays = logAgeThresholdDays
        self.cleanupLevel = cleanupLevel
        self.trashSafeForUndo = trashSafeForUndo
    }

    /// Move to Trash applies to levels 2 & 3; Safe only when undo is requested.
    public var effectiveMoveToTrash: Bool {
        guard let level = cleanupLevel else { return false }
        if level == .safe { return trashSafeForUndo }
        return moveToTrash
    }
}
