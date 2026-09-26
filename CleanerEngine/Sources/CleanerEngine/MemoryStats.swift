import Foundation

/// How hard macOS is working to find memory, as the kernel reports it. This is
/// the signal Activity Monitor's pressure graph follows, and the only honest
/// answer to "do I need more free memory": a Mac with little free memory but
/// normal pressure is using its RAM well, not running out of it.
public enum MemoryPressure: Int, Codable, Sendable, Comparable, CaseIterable {
    case normal = 1
    case warning = 2
    case critical = 4

    /// The kernel's `kern.memorystatus_vm_pressure_level`. Anything unexpected
    /// reads as normal, so a changed encoding never raises a false alarm.
    public init(kernelLevel: Int32) {
        switch kernelLevel {
        case 4: self = .critical
        case 2: self = .warning
        default: self = .normal
        }
    }

    public static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Raw page counts from the kernel's VM statistics, in pages. Kept separate from
/// the Mach call that fills them so the arithmetic below is testable anywhere.
public struct VMPageCounts: Equatable, Sendable {
    public var free: UInt64
    public var active: UInt64
    public var inactive: UInt64
    public var speculative: UInt64
    public var wired: UInt64
    /// Pages the compressor occupies (not the pages it holds compressed).
    public var compressed: UInt64
    public var purgeable: UInt64
    /// File-backed pages: the file cache.
    public var fileBacked: UInt64
    /// Anonymous pages: memory processes allocated for themselves.
    public var anonymous: UInt64

    public init(
        free: UInt64 = 0, active: UInt64 = 0, inactive: UInt64 = 0, speculative: UInt64 = 0,
        wired: UInt64 = 0, compressed: UInt64 = 0, purgeable: UInt64 = 0,
        fileBacked: UInt64 = 0, anonymous: UInt64 = 0
    ) {
        self.free = free
        self.active = active
        self.inactive = inactive
        self.speculative = speculative
        self.wired = wired
        self.compressed = compressed
        self.purgeable = purgeable
        self.fileBacked = fileBacked
        self.anonymous = anonymous
    }
}

/// The memory picture at one moment, split the way Activity Monitor splits it.
///
/// "Used" is app memory, wired memory, and what the compressor occupies. Cached
/// files are not used: macOS keeps recently read files in otherwise idle RAM and
/// hands that memory to any app that asks, instantly. That is why a healthy Mac
/// shows little free memory, and why "freeing" the cache buys nothing.
public struct MemorySnapshot: Equatable, Sendable, Codable {
    public let totalBytes: Int64
    public let appBytes: Int64
    public let wiredBytes: Int64
    public let compressedBytes: Int64
    public let cachedFilesBytes: Int64
    public let swapUsedBytes: Int64
    public let swapTotalBytes: Int64
    public let pressure: MemoryPressure
    public let sampledAt: Date

    public init(
        totalBytes: Int64,
        appBytes: Int64,
        wiredBytes: Int64,
        compressedBytes: Int64,
        cachedFilesBytes: Int64,
        swapUsedBytes: Int64,
        swapTotalBytes: Int64,
        pressure: MemoryPressure,
        sampledAt: Date
    ) {
        self.totalBytes = totalBytes
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.cachedFilesBytes = cachedFilesBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.pressure = pressure
        self.sampledAt = sampledAt
    }

    /// App, wired, and compressed memory: what Activity Monitor calls Memory Used.
    public var usedBytes: Int64 { appBytes + wiredBytes + compressedBytes }

    /// Memory an app can have right now without anything being swapped out:
    /// genuinely free pages plus the file cache macOS gives back on demand.
    public var availableBytes: Int64 { max(0, totalBytes - usedBytes) }

    /// Pages holding nothing at all. Small on a healthy Mac, by design.
    public var freeBytes: Int64 { max(0, totalBytes - usedBytes - cachedFilesBytes) }

    /// Share of physical memory in use, 0...1.
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    /// Build a snapshot from kernel page counts.
    ///
    /// App memory is anonymous memory minus the purgeable part (which apps have
    /// marked as droppable); cached files are file-backed pages plus purgeable
    /// ones. Every figure is clamped so rounding or a racing sample can never
    /// report more memory than the machine has.
    public static func from(
        pages: VMPageCounts,
        pageSize: UInt64,
        totalBytes: Int64,
        swapUsedBytes: Int64,
        swapTotalBytes: Int64,
        pressure: MemoryPressure,
        sampledAt: Date
    ) -> MemorySnapshot {
        let size = Int64(clamping: pageSize)
        func bytes(_ count: UInt64) -> Int64 {
            let (product, overflow) = Int64(clamping: count).multipliedReportingOverflow(by: size)
            return overflow ? .max : product
        }
        func sum(_ a: Int64, _ b: Int64) -> Int64 {
            let (total, overflow) = a.addingReportingOverflow(b)
            return overflow ? .max : total
        }
        let total = max(0, totalBytes)
        let anonymous = pages.anonymous > pages.purgeable ? pages.anonymous - pages.purgeable : 0
        var remaining = total
        func take(_ value: Int64) -> Int64 {
            let taken = min(max(0, value), remaining)
            remaining -= taken
            return taken
        }
        // Wired first: the kernel's share is the least negotiable, so it is the
        // last figure a clamp should shave.
        let wired = take(bytes(pages.wired))
        let compressed = take(bytes(pages.compressed))
        let app = take(bytes(anonymous))
        let cached = take(sum(bytes(pages.fileBacked), bytes(pages.purgeable)))
        return MemorySnapshot(
            totalBytes: total,
            appBytes: app,
            wiredBytes: wired,
            compressedBytes: compressed,
            cachedFilesBytes: cached,
            swapUsedBytes: max(0, swapUsedBytes),
            swapTotalBytes: max(0, swapTotalBytes),
            pressure: pressure,
            sampledAt: sampledAt
        )
    }

    /// RAM sizes read in binary units: a 16 GB Mac is 16 GB, not 17.18.
    public static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }
}
