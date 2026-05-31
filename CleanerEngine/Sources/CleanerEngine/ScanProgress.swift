import Foundation

public struct ScanProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let currentTargetName: String

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    public init(completed: Int, total: Int, currentTargetName: String) {
        self.completed = completed
        self.total = total
        self.currentTargetName = currentTargetName
    }
}

public typealias ScanProgressHandler = @Sendable (ScanProgress) -> Void
