import Foundation

public enum CleanupLevel: Int, CaseIterable, Codable, Sendable, Comparable, Identifiable {
    case safe = 1
    case developer = 2
    case deep = 3

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .safe: return "Level 1: Safe"
        case .developer: return "Level 2: Developer"
        case .deep: return "Level 3: Deep"
        }
    }

    public var subtitle: String {
        switch self {
        case .safe:
            return "User caches, logs, Trash: zero functional impact"
        case .developer:
            return "DerivedData, simulators, package caches: may require rebuilds"
        case .deep:
            return "Installers, Xcode archives, old system logs: manual selection"
        }
    }

    public static func < (lhs: CleanupLevel, rhs: CleanupLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
