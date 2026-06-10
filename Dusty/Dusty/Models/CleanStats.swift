import Foundation
import CleanerEngine

/// One finished clean, for the recent-history list.
struct CleanRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let level: Int
    let bytes: Int64
    let items: Int

    init(id: UUID = UUID(), date: Date = Date(), level: Int, bytes: Int64, items: Int) {
        self.id = id
        self.date = date
        self.level = level
        self.bytes = bytes
        self.items = items
    }
}

/// Lifetime cleaning stats, separate from the deletion log on purpose: the log
/// rotates once it grows past a size cap, so an all-time total has to be kept
/// as its own running figure.
@MainActor
final class CleanStatsStore: ObservableObject {
    static let shared = CleanStatsStore()

    @Published private(set) var lifetimeBytes: Int64
    @Published private(set) var cleanCount: Int
    @Published private(set) var firstCleanAt: Date?
    @Published private(set) var recent: [CleanRecord]

    private let defaults: UserDefaults
    private static let maxRecent = 8

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lifetimeBytes = (defaults.object(forKey: "stats.lifetimeBytes") as? NSNumber)?.int64Value ?? 0
        cleanCount = defaults.integer(forKey: "stats.cleanCount")
        firstCleanAt = defaults.object(forKey: "stats.firstCleanAt") as? Date
        if let data = defaults.data(forKey: "stats.recent"),
           let decoded = try? JSONDecoder().decode([CleanRecord].self, from: data) {
            recent = decoded
        } else {
            recent = []
        }
    }

    func record(level: CleanupLevel, bytes: Int64, items: Int) {
        guard bytes > 0 else { return }
        lifetimeBytes += bytes
        cleanCount += 1
        if firstCleanAt == nil { firstCleanAt = Date() }
        recent.insert(CleanRecord(level: level.rawValue, bytes: bytes, items: items), at: 0)
        recent = Array(recent.prefix(Self.maxRecent))
        persist()
    }

    /// The user undid the last clean: the space came back, so the books must too.
    func unrecordLast(bytes: Int64) {
        lifetimeBytes = max(0, lifetimeBytes - bytes)
        cleanCount = max(0, cleanCount - 1)
        if let last = recent.first, last.bytes == bytes {
            recent.removeFirst()
        }
        persist()
    }

    private func persist() {
        defaults.set(NSNumber(value: lifetimeBytes), forKey: "stats.lifetimeBytes")
        defaults.set(cleanCount, forKey: "stats.cleanCount")
        defaults.set(firstCleanAt, forKey: "stats.firstCleanAt")
        if let data = try? JSONEncoder().encode(recent) {
            defaults.set(data, forKey: "stats.recent")
        }
    }
}
