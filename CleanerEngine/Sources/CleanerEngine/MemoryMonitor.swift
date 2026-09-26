import Foundation
import Darwin
import CoreAudio

/// Reads the system's memory figures: the same kernel counters Activity Monitor
/// uses, plus swap and the pressure level. Unprivileged and read-only.
public struct MemoryMonitor: Sendable {
    public init() {}

    /// The machine's memory right now, or nil if the kernel would not say.
    public func snapshot(now: Date = Date()) -> MemorySnapshot? {
        guard let pages = Self.pageCounts() else { return nil }
        let swap = Self.swapUsage()
        let level = Self.sysctlInt32("kern.memorystatus_vm_pressure_level") ?? 1
        return MemorySnapshot.from(
            pages: pages,
            pageSize: Self.pageSize,
            totalBytes: Int64(clamping: ProcessInfo.processInfo.physicalMemory),
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            pressure: MemoryPressure(kernelLevel: level),
            sampledAt: now
        )
    }

    /// Fetched once: every `mach_host_self()` call adds a send right to the
    /// host port, so asking on every sample would slowly leak them.
    private static let host: host_t = mach_host_self()

    private static let pageSize: UInt64 = {
        var size: vm_size_t = 0
        if host_page_size(host, &size) == KERN_SUCCESS, size > 0 { return UInt64(size) }
        let fallback = sysconf(_SC_PAGESIZE)
        return fallback > 0 ? UInt64(fallback) : 4096
    }()

    private static func pageCounts() -> VMPageCounts? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return VMPageCounts(
            free: UInt64(stats.free_count),
            active: UInt64(stats.active_count),
            inactive: UInt64(stats.inactive_count),
            speculative: UInt64(stats.speculative_count),
            wired: UInt64(stats.wire_count),
            compressed: UInt64(stats.compressor_page_count),
            purgeable: UInt64(stats.purgeable_count),
            fileBacked: UInt64(stats.external_page_count),
            anonymous: UInt64(stats.internal_page_count)
        )
    }

    private static func swapUsage() -> (used: Int64, total: Int64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (Int64(clamping: usage.xsu_used), Int64(clamping: usage.xsu_total))
    }

    static func sysctlInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}

/// Samples every process the current user owns: its footprint, its executable,
/// and the process macOS holds responsible for it. Other users' and the system's
/// processes are skipped; they are not the user's to quit.
public enum ProcessMemoryScanner {
    public static func sample() -> [ProcessMemorySample] {
        let uid = getuid()
        let capacity = Int(proc_listallpids(nil, 0))
        guard capacity > 0 else { return [] }
        // Headroom for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: capacity + 64)
        let found = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride)))
        guard found > 0 else { return [] }

        var samples: [ProcessMemorySample] = []
        samples.reserveCapacity(found)
        for pid in pids.prefix(min(found, pids.count)) where pid > 1 {
            guard owner(of: pid) == uid,
                  let footprint = footprint(of: pid),
                  let path = executablePath(of: pid) else { continue }
            samples.append(ProcessMemorySample(
                pid: pid,
                responsiblePID: responsiblePID(for: pid),
                executablePath: path,
                footprintBytes: footprint
            ))
        }
        return samples
    }

    private static func owner(of pid: pid_t) -> uid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) > 0 else { return nil }
        return info.pbi_uid
    }

    private static func footprint(of pid: pid_t) -> Int64? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        return Int64(clamping: usage.ri_phys_footprint)
    }

    private static func executablePath(of pid: pid_t) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is 4 * MAXPATHLEN.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// `responsibility_get_pid_responsible_for_pid` is how macOS attributes a
    /// helper to its app (Activity Monitor and privacy prompts use the same
    /// link). It is not in a public header, so it is looked up at run time and
    /// everything falls back to path-based grouping if it ever disappears.
    private static let responsibleSymbol: UInt = {
        // RTLD_DEFAULT: search every image already loaded.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return 0
        }
        return UInt(bitPattern: symbol)
    }()

    private static func responsiblePID(for pid: pid_t) -> pid_t {
        guard let pointer = UnsafeRawPointer(bitPattern: responsibleSymbol) else { return pid }
        typealias Lookup = @convention(c) (pid_t) -> pid_t
        let lookup = unsafeBitCast(pointer, to: Lookup.self)
        let responsible = lookup(pid)
        return responsible > 0 ? responsible : pid
    }
}

/// Which processes are playing or recording sound right now. An app on a call
/// or playing music in the background is in use, whatever its window says.
public enum AudioActivityProbe {
    public struct Activity: Sendable, Equatable {
        public var outputPIDs: Set<Int32>
        public var inputPIDs: Set<Int32>

        public init(outputPIDs: Set<Int32> = [], inputPIDs: Set<Int32> = []) {
            self.outputPIDs = outputPIDs
            self.inputPIDs = inputPIDs
        }
    }

    /// Nil when this macOS cannot say (per-process audio objects arrived in 14.2).
    /// Reading these properties needs no permission: it lists who is doing audio
    /// work, it never listens to any of it.
    public static func current() -> Activity? {
        guard #available(macOS 14.2, *) else { return nil }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        guard count > 0 else { return Activity() }
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return nil }

        var activity = Activity()
        for object in objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride) {
            guard let raw = uint32(of: object, kAudioProcessPropertyPID) else { continue }
            let pid = pid_t(bitPattern: raw)
            guard pid > 0 else { continue }
            if (uint32(of: object, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0 {
                activity.outputPIDs.insert(pid)
            }
            if (uint32(of: object, kAudioProcessPropertyIsRunningInput) ?? 0) != 0 {
                activity.inputPIDs.insert(pid)
            }
        }
        return activity
    }

    /// Every property read here is a 32-bit value (a pid or a flag).
    private static func uint32(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
