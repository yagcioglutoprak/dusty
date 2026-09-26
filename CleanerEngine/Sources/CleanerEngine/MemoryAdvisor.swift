import Foundation

/// What the advisor needs to know about one running app. The app layer fills it
/// from AppKit (frontmost app, activation times) and CoreAudio; the rules below
/// stay pure so they can be tested.
public struct MemoryCandidate: Sendable, Hashable {
    public let id: String
    public let bundleIdentifier: String?
    public let footprintBytes: Int64
    public let isFrontmost: Bool
    /// When the app last stopped being the frontmost app. Nil when it has not
    /// been frontmost since Dusty started watching.
    public let lastActiveAt: Date?
    public let isPlayingAudio: Bool
    public let isUsingMicrophone: Bool

    public init(
        id: String,
        bundleIdentifier: String?,
        footprintBytes: Int64,
        isFrontmost: Bool,
        lastActiveAt: Date?,
        isPlayingAudio: Bool = false,
        isUsingMicrophone: Bool = false
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.footprintBytes = footprintBytes
        self.isFrontmost = isFrontmost
        self.lastActiveAt = lastActiveAt
        self.isPlayingAudio = isPlayingAudio
        self.isUsingMicrophone = isUsingMicrophone
    }
}

/// Decides which apps are worth offering to quit when memory is wanted back.
///
/// On macOS the only memory worth reclaiming is memory an app is holding: the
/// file cache is handed back instantly on demand, and forcing it out (`purge`)
/// needs root and just makes the next file reads slower. So the advisor never
/// "frees RAM"; it points at big apps nobody has used for a while. Nothing here
/// quits anything, and the panel always asks first.
public enum MemoryAdvisor {
    /// Apps holding less than this are not worth a suggestion.
    public static let minimumSuggestedBytes: Int64 = 300 * 1_048_576
    /// How long an app has to sit in the background before it counts as idle.
    public static let defaultIdleThreshold: TimeInterval = 3600

    /// Apps never suggested, however idle they look: quitting them ends work
    /// that runs without anyone looking at the window.
    public static let neverSuggestedBundleIDs: Set<String> = [
        // Terminals: quitting one ends every shell and job running inside it.
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
        "com.github.wez.wezterm", "org.alacritty", "io.alacritty", "com.mitchellh.ghostty", "co.zeit.hyper",
        // Virtual machines and containers: quitting stops everything inside.
        "com.docker.docker", "dev.kdrag0n.MacVirt", "com.utmapp.UTM", "com.parallels.desktop.console",
        "com.vmware.fusion", "org.virtualbox.app.VirtualBox",
        // Calls, streaming, and recording, which carry on in the background.
        "us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.apple.FaceTime", "com.hnc.Discord",
        "com.obsproject.obs-studio", "com.apple.QuickTimePlayerX", "com.apple.ScreenSharing",
        // Downloads and transfers in flight.
        "org.m0k.transmission", "com.apple.appstore",
    ]

    /// Media players, skipped only when Dusty cannot tell whether they are
    /// playing (macOS before 14.2 has no per-process audio activity).
    public static let mediaBundleIDs: Set<String> = [
        "com.apple.Music", "com.spotify.client", "com.apple.podcasts", "com.apple.TV",
        "org.videolan.vlc", "com.colliderli.iina", "com.tidal.desktop", "com.deezer.deezer-desktop",
    ]

    /// The apps to offer for quitting: big, in the background, idle for at least
    /// `idleThreshold`, and not doing anything audible.
    ///
    /// An app that has not been frontmost since `trackingSince` has been idle at
    /// least that long, so a freshly started Dusty suggests nothing until it has
    /// watched for a full idle period.
    public static func suggestedIDs(
        candidates: [MemoryCandidate],
        now: Date,
        trackingSince: Date,
        idleThreshold: TimeInterval = defaultIdleThreshold,
        audioActivityKnown: Bool
    ) -> Set<String> {
        Set(candidates.compactMap { candidate -> String? in
            guard !candidate.isFrontmost,
                  candidate.footprintBytes >= minimumSuggestedBytes,
                  !candidate.isPlayingAudio,
                  !candidate.isUsingMicrophone else { return nil }
            if let id = candidate.bundleIdentifier {
                if neverSuggestedBundleIDs.contains(id) { return nil }
                if !audioActivityKnown && mediaBundleIDs.contains(id) { return nil }
            }
            let idleSince = candidate.lastActiveAt ?? trackingSince
            guard now.timeIntervalSince(idleSince) >= idleThreshold else { return nil }
            return candidate.id
        })
    }
}

// MARK: - Growth

/// An app whose memory climbed well past where it started.
public struct MemoryGrowth: Sendable, Hashable {
    public let fromBytes: Int64
    public let toBytes: Int64
    /// When the lower figure was measured.
    public let since: Date

    public init(fromBytes: Int64, toBytes: Int64, since: Date) {
        self.fromBytes = fromBytes
        self.toBytes = toBytes
        self.since = since
    }

    public var grownBytes: Int64 { toBytes - fromBytes }
}

/// Recent footprints per app, for spotting one that keeps growing: a leaky
/// Electron app, a browser that has been open for a week. Relaunching such an
/// app gives the growth back; Dusty only points it out.
public struct MemoryFootprintHistory: Sendable {
    public struct Sample: Sendable, Hashable {
        public let date: Date
        public let bytes: Int64
    }

    /// How far back growth is measured.
    public static let window: TimeInterval = 6 * 3600
    /// The baseline has to be at least this old, or a burst reads as a trend.
    public static let minimumSpan: TimeInterval = 30 * 60
    /// Growth smaller than this is not worth mentioning.
    public static let minimumGrowthBytes: Int64 = 512 * 1_048_576
    /// And it has to be large relative to where the app started.
    public static let minimumGrowthRatio = 1.5

    private var samples: [String: [Sample]] = [:]
    private var generation: [String: Int32] = [:]

    public init() {}

    /// Record one reading per app. `generation` is the app's process id: a new
    /// one means the app was relaunched, which starts its history over. Apps
    /// missing from `readings` have quit, and their history goes with them.
    public mutating func record(_ readings: [(id: String, generation: Int32, bytes: Int64)], at date: Date) {
        var next: [String: [Sample]] = [:]
        var nextGeneration: [String: Int32] = [:]
        let cutoff = date.addingTimeInterval(-Self.window)
        for reading in readings {
            var series = generation[reading.id] == reading.generation ? (samples[reading.id] ?? []) : []
            series.removeAll { $0.date < cutoff }
            series.append(Sample(date: date, bytes: reading.bytes))
            next[reading.id] = series
            nextGeneration[reading.id] = reading.generation
        }
        samples = next
        generation = nextGeneration
    }

    public func series(for id: String) -> [Sample] {
        samples[id] ?? []
    }

    /// How much `id` has grown: from its lowest reading at least `minimumSpan`
    /// old up to its latest one. Nil unless the growth is both large and large
    /// relative to the starting point.
    public func growth(for id: String, now: Date) -> MemoryGrowth? {
        guard let series = samples[id], let latest = series.last else { return nil }
        let windowStart = now.addingTimeInterval(-Self.window)
        let baselineCutoff = now.addingTimeInterval(-Self.minimumSpan)
        let eligible = series.filter { $0.date >= windowStart && $0.date <= baselineCutoff }
        guard let baseline = eligible.min(by: { $0.bytes < $1.bytes }), baseline.bytes > 0 else { return nil }
        let grown = latest.bytes - baseline.bytes
        guard grown >= Self.minimumGrowthBytes,
              Double(latest.bytes) >= Double(baseline.bytes) * Self.minimumGrowthRatio else { return nil }
        return MemoryGrowth(fromBytes: baseline.bytes, toBytes: latest.bytes, since: baseline.date)
    }
}

// MARK: - Alerts

/// When a "memory is running low" notification is worth sending: pressure has
/// stayed high, not merely spiked, and it is the first alert of this episode.
public enum MemoryAlertPolicy {
    /// Critical pressure has to hold this long.
    public static let criticalSustain: TimeInterval = 2 * 60
    /// Warning pressure has to hold much longer: an 8 GB Mac can sit in it for a
    /// while without anyone noticing a slowdown.
    public static let warningSustain: TimeInterval = 20 * 60
    /// At most one alert per this long, whatever the pressure does.
    public static let cooldown: TimeInterval = 6 * 3600

    /// - Parameters:
    ///   - elevatedSince: start of the current unbroken run at warning or above.
    ///   - criticalSince: start of the current unbroken run at critical.
    ///   - lastAlertAt: when the previous alert went out.
    public static func shouldAlert(
        pressure: MemoryPressure,
        elevatedSince: Date?,
        criticalSince: Date?,
        lastAlertAt: Date?,
        now: Date
    ) -> Bool {
        guard pressure >= .warning, let elevatedSince else { return false }
        if let lastAlertAt {
            // One alert per episode, and never two inside the cooldown.
            if lastAlertAt >= elevatedSince { return false }
            if now.timeIntervalSince(lastAlertAt) < cooldown { return false }
        }
        if pressure == .critical, let criticalSince, now.timeIntervalSince(criticalSince) >= criticalSustain {
            return true
        }
        return now.timeIntervalSince(elevatedSince) >= warningSustain
    }
}
