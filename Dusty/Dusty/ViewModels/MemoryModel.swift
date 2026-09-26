import Foundation
import AppKit
import CleanerEngine

/// A running app as the memory screen lists it: its memory counted together
/// with every helper process working for it.
struct RunningAppMemory: Identifiable, Equatable {
    /// The app's bundle path, stable across refreshes.
    let id: String
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    let pid: pid_t
    /// When this copy of the app started; with the pid, it tells a relaunched
    /// or recycled process apart from the one that was listed.
    let launchDate: Date?
    let footprintBytes: Int64
    let processCount: Int
    let icon: NSImage?
    let isFrontmost: Bool
    /// When the app last stopped being the frontmost app, if Dusty saw it.
    let lastActiveAt: Date?
    /// Unused since at least then: the last activation, or when Dusty started
    /// watching if it has not been frontmost since.
    let idleSince: Date
    let isPlayingAudio: Bool
    let isUsingMicrophone: Bool

    /// Terminals, virtual machines, calls: never suggested, and not offered a
    /// one-click Relaunch either, because what runs inside them would end.
    var isNeverSuggested: Bool {
        bundleIdentifier.map { MemoryAdvisor.neverSuggestedBundleIDs.contains($0) } ?? false
    }
}

/// The menu bar's RAM figure on its own, so the app scene redraws when the
/// rounded percent changes rather than on every sample the memory screen takes.
@MainActor
final class MemoryMenuBarFigure: ObservableObject {
    @Published private(set) var usedPercent: Int?

    func update(_ percent: Int?) {
        if percent != usedPercent { usedPercent = percent }
    }
}

/// One reading for the "memory in use" sparkline.
struct MemoryUsagePoint: Equatable {
    let date: Date
    let usedFraction: Double
    let pressure: MemoryPressure
}

/// What a quit (or a relaunch) did, for the receipt.
struct MemoryQuitReceipt: Equatable {
    struct QuitApp: Equatable, Identifiable {
        let id: String
        let name: String
        let bundleURL: URL?
        let bytes: Int64
    }

    let quit: [QuitApp]
    /// Apps that were asked to quit and are still open, most likely showing a
    /// "save changes?" dialog.
    let stillOpen: [String]
    let availableBefore: Int64
    let availableAfter: Int64
    let isRelaunch: Bool

    var freedBytes: Int64 { quit.reduce(0) { $0 + $1.bytes } }
}

/// Everything the memory screen shows, and the one thing it does: quit apps the
/// normal way, after asking, with a way back.
///
/// Dusty never force-quits, never kills a process, and never runs `purge`
/// (which needs root and only evicts the file cache macOS would hand back on
/// its own anyway). The memory worth reclaiming is memory an app is holding, and
/// the honest way to get it back is to quit or relaunch that app.
@MainActor
final class MemoryModel: ObservableObject {
    @Published private(set) var snapshot: MemorySnapshot?
    @Published private(set) var apps: [RunningAppMemory] = []
    /// Stand-alone processes (servers, tools) holding a lot. Shown, never quit.
    @Published private(set) var backgroundProcesses: [AppMemoryUsage] = []
    @Published private(set) var suggestedIDs: Set<String> = []
    @Published private(set) var growth: [String: MemoryGrowth] = [:]
    @Published private(set) var usageHistory: [MemoryUsagePoint] = []
    @Published private(set) var hasLoadedApps = false
    @Published var selection: Set<String> = []
    /// Apps awaiting the confirmation sheet.
    @Published var pendingQuit: [RunningAppMemory]?
    /// The app awaiting the Relaunch confirmation.
    @Published var pendingRelaunch: RunningAppMemory?
    @Published private(set) var quittingIDs: Set<String> = []
    @Published private(set) var receipt: MemoryQuitReceipt?
    /// While set, the receipt offers to reopen what was quit.
    @Published private(set) var reopenDeadline: Date?
    @Published var errorMessage: String?

    /// How long the receipt offers Reopen: the same eight seconds as a clean's Undo.
    static let reopenWindow: TimeInterval = 8
    /// Stand-alone processes below this are not worth a line.
    private static let backgroundMinimumBytes: Int64 = 150 * 1_048_576
    private static let lastAlertKey = "memoryLastAlertAt"

    let menuBarFigure = MemoryMenuBarFigure()
    private let monitor = MemoryMonitor()
    private let startsServices: Bool
    private let trackingSince = Date()
    private var lastActive: [pid_t: Date] = [:]
    private var history = MemoryFootprintHistory()
    private var lastHistoryRecord: Date?
    private var lastAppsRefresh: Date?
    private var isRefreshingApps = false
    private var isLive = false
    private var userEditedSelection = false
    private var loopTask: Task<Void, Never>?
    private var reopenTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var elevatedSince: Date?
    private var criticalSince: Date?

    /// False for an inert model (rendered snapshots): no sampling, no observers.
    init(startsServices: Bool = true) {
        self.startsServices = startsServices
        guard startsServices else { return }
        observeActivations()
        sampleSystem()
        startLoop()
    }

    deinit {
        loopTask?.cancel()
        reopenTask?.cancel()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Derived

    var totalAppBytes: Int64 { apps.reduce(0) { $0 + $1.footprintBytes } }

    var suggestedApps: [RunningAppMemory] { apps.filter { suggestedIDs.contains($0.id) } }

    var suggestedBytes: Int64 { suggestedApps.reduce(0) { $0 + $1.footprintBytes } }

    var selectedApps: [RunningAppMemory] { apps.filter { selection.contains($0.id) } }

    var selectedBytes: Int64 { selectedApps.reduce(0) { $0 + $1.footprintBytes } }

    var isQuitting: Bool { !quittingIDs.isEmpty }


    /// Available memory once `bytes` more is given back, capped at the total.
    func projectedAvailable(afterFreeing bytes: Int64) -> Int64 {
        guard let snapshot else { return max(0, bytes) }
        return min(snapshot.totalBytes, snapshot.availableBytes + max(0, bytes))
    }

    // MARK: - Sampling

    /// The memory screen samples every couple of seconds while it is on screen,
    /// and the app list every few; the rest of the time a slow heartbeat keeps
    /// the menu bar figure, the pressure alert, and the growth history current.
    func setLive(_ live: Bool) {
        guard startsServices, live != isLive else { return }
        isLive = live
        if live {
            userEditedSelection = false
            sampleSystem()
            Task { await refreshApps() }
        }
        startLoop()
    }

    /// Called when the panel opens: a fresh figure, and fresh suggestions if the
    /// last look at the apps is getting old.
    func panelOpened() {
        guard startsServices else { return }
        sampleSystem()
        if lastAppsRefresh.map({ Date().timeIntervalSince($0) > 60 }) ?? true {
            Task { await refreshApps() }
        }
    }

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let seconds = await self?.tick() else { return }
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    /// One heartbeat. Returns how long to wait before the next one.
    private func tick() async -> TimeInterval {
        sampleSystem()
        let appsInterval: TimeInterval = isLive ? 3 : 300
        if lastAppsRefresh.map({ Date().timeIntervalSince($0) >= appsInterval }) ?? true {
            await refreshApps()
        }
        return isLive ? 2 : 30
    }

    private func sampleSystem() {
        guard let fresh = monitor.snapshot() else { return }
        snapshot = fresh
        menuBarFigure.update(Int((fresh.usedFraction * 100).rounded()))
        recordUsage(fresh)
        trackPressure(fresh)
    }

    /// Up to an hour of readings, at most one per 20 seconds.
    private func recordUsage(_ snapshot: MemorySnapshot) {
        if let last = usageHistory.last, snapshot.sampledAt.timeIntervalSince(last.date) < 20 { return }
        usageHistory.append(MemoryUsagePoint(date: snapshot.sampledAt, usedFraction: snapshot.usedFraction,
                                             pressure: snapshot.pressure))
        let cutoff = snapshot.sampledAt.addingTimeInterval(-3600)
        usageHistory.removeAll { $0.date < cutoff }
    }

    func refreshApps() async {
        guard startsServices, !isRefreshingApps else { return }
        isRefreshingApps = true
        defer { isRefreshingApps = false }
        let own = getpid()
        let appPIDs = Self.appPIDs()
        // Walking every process takes a few milliseconds: off the main actor.
        let (groups, audio) = await Task.detached(priority: .utility) {
            (AppMemoryGrouping.group(ProcessMemoryScanner.sample(), appPIDs: appPIDs, excludingPIDs: [own]),
             AudioActivityProbe.current())
        }.value
        apply(groups: groups, audio: audio, now: Date())
    }

    private func apply(groups: [AppMemoryUsage], audio: AudioActivityProbe.Activity?, now: Date) {
        let workspace = NSWorkspace.shared
        let frontmost = workspace.frontmostApplication?.processIdentifier
        var groupByPID: [pid_t: AppMemoryUsage] = [:]
        for group in groups {
            for pid in group.pids { groupByPID[pid] = group }
        }

        var claimed = Set<String>()
        var listed: [RunningAppMemory] = []
        for app in workspace.runningApplications where Self.isQuittable(app) {
            guard let group = groupByPID[app.processIdentifier], !claimed.contains(group.id) else { continue }
            claimed.insert(group.id)
            let pids = Set(group.pids)
            let lastUsed = lastActive[app.processIdentifier]
            // Idle since the later of its last use and its launch: an app opened
            // (or reopened) a minute ago has not been idle for hours, whenever
            // Dusty started watching.
            let idleSince = app.processIdentifier == frontmost
                ? now
                : max(lastUsed ?? trackingSince, app.launchDate ?? trackingSince)
            listed.append(RunningAppMemory(
                id: group.id,
                name: app.localizedName ?? group.name,
                bundleIdentifier: app.bundleIdentifier,
                bundleURL: app.bundleURL,
                pid: app.processIdentifier,
                launchDate: app.launchDate,
                footprintBytes: group.footprintBytes,
                processCount: group.processCount,
                icon: app.icon,
                isFrontmost: app.processIdentifier == frontmost,
                lastActiveAt: lastUsed,
                idleSince: idleSince,
                isPlayingAudio: audio.map { !$0.outputPIDs.isDisjoint(with: pids) } ?? false,
                isUsingMicrophone: audio.map { !$0.inputPIDs.isDisjoint(with: pids) } ?? false
            ))
        }
        listed.sort { $0.footprintBytes != $1.footprintBytes ? $0.footprintBytes > $1.footprintBytes : $0.name < $1.name }

        let candidates = listed.map {
            MemoryCandidate(
                id: $0.id,
                bundleIdentifier: $0.bundleIdentifier,
                footprintBytes: $0.footprintBytes,
                isFrontmost: $0.isFrontmost,
                lastActiveAt: $0.idleSince,
                isPlayingAudio: $0.isPlayingAudio,
                isUsingMicrophone: $0.isUsingMicrophone
            )
        }
        let suggested = MemoryAdvisor.suggestedIDs(
            candidates: candidates,
            now: now,
            trackingSince: trackingSince,
            idleThreshold: TimeInterval(max(15, AppSettings.shared.memoryIdleMinutes)) * 60,
            audioActivityKnown: audio != nil
        )

        // Growth needs readings minutes apart, not seconds: record every five,
        // and at once when an app was relaunched or appeared, so a relaunch
        // clears its growth on the spot instead of up to five minutes later.
        let relaunched = listed.contains { history.generation(for: $0.id) != $0.pid }
        if relaunched || lastHistoryRecord.map({ now.timeIntervalSince($0) >= 300 }) ?? true {
            history.record(listed.map { (id: $0.id, generation: $0.pid, bytes: $0.footprintBytes) }, at: now)
            lastHistoryRecord = now
        }
        var grown: [String: MemoryGrowth] = [:]
        for app in listed {
            if let found = history.growth(for: app.id, now: now) { grown[app.id] = found }
        }

        apps = listed
        suggestedIDs = suggested
        growth = grown
        backgroundProcesses = Array(groups.filter {
            !$0.isApp && !claimed.contains($0.id) && $0.footprintBytes >= Self.backgroundMinimumBytes
        }.prefix(5))
        // Until someone ticks a box, the selection follows the suggestions.
        let ids = Set(listed.map(\.id))
        if userEditedSelection {
            selection.formIntersection(ids)
        } else {
            selection = suggested
        }
        lastAppsRefresh = now
        hasLoadedApps = true
    }

    /// Apps a person would recognize and could quit themselves: Dock apps, and
    /// third-party menu bar apps. Never Dusty, Finder, or the pieces of macOS
    /// that relaunch themselves the moment they quit.
    static func isQuittable(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated, app.processIdentifier != getpid() else { return false }
        if let id = app.bundleIdentifier, protectedBundleIDs.contains(id) || id == Bundle.main.bundleIdentifier {
            return false
        }
        let path = app.bundleURL?.path ?? ""
        if path.hasPrefix("/System/Library/") || path.hasPrefix("/Library/Apple/") { return false }
        switch app.activationPolicy {
        case .regular:
            return true
        case .accessory:
            return !(app.bundleIdentifier ?? "").hasPrefix("com.apple.") && !path.hasPrefix("/System/")
        default:
            return false
        }
    }

    /// Processes macOS runs as apps of their own (Dock and menu bar apps), so
    /// an app nested inside another's bundle keeps its own line.
    private static func appPIDs() -> Set<Int32> {
        Set(NSWorkspace.shared.runningApplications.compactMap { app in
            app.activationPolicy == .prohibited ? nil : app.processIdentifier
        })
    }

    private static let protectedBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver",
        "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.Spotlight",
        "com.apple.WindowManager",
    ]

    // MARK: - Activity

    /// When each app last stopped being frontmost. Dusty runs all the time, so
    /// it can say "not used for two hours" instead of guessing from window state.
    private func observeActivations() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            Task { @MainActor in self?.lastActive[pid] = Date() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            Task { @MainActor in self?.appTerminated(pid) }
        })
    }

    private func appTerminated(_ pid: pid_t) {
        lastActive[pid] = nil
        // An app quit on its own: drop its row (and its tick) now rather than on
        // the next tick.
        if let gone = apps.first(where: { $0.pid == pid }) {
            apps.removeAll { $0.pid == pid }
            selection.remove(gone.id)
            if isLive { Task { await refreshApps() } }
        }
    }

    // MARK: - Selection

    func toggle(_ id: String) {
        userEditedSelection = true
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func clearSelection() {
        userEditedSelection = true
        selection = []
    }

    // MARK: - Quit

    /// Ask before quitting: the confirmation lists every app and its memory.
    func requestQuit(_ ids: Set<String>? = nil) {
        let chosen = apps.filter { (ids ?? selection).contains($0.id) }
        guard !chosen.isEmpty else {
            errorMessage = L10n.t("memory.error.noSelection", "Tick at least one app to quit.")
            return
        }
        errorMessage = nil
        pendingQuit = chosen
    }

    func cancelQuit() {
        pendingQuit = nil
    }

    func confirmQuit() async {
        guard let chosen = pendingQuit else { return }
        pendingQuit = nil
        await quit(chosen, relaunch: false)
    }

    /// Ask before relaunching: it quits the app, and apps hold state.
    func requestRelaunch(_ app: RunningAppMemory) {
        guard app.bundleURL != nil else { return }
        errorMessage = nil
        pendingRelaunch = app
    }

    func cancelRelaunch() {
        pendingRelaunch = nil
    }

    /// Quit and reopen one app: gives back what it has piled up since launch.
    func confirmRelaunch() async {
        guard let app = pendingRelaunch else { return }
        pendingRelaunch = nil
        await quit([app], relaunch: true)
    }

    private func quit(_ targets: [RunningAppMemory], relaunch: Bool) async {
        guard !isQuitting else { return }
        finalizeReopen()
        errorMessage = nil
        let before = monitor.snapshot()?.availableBytes ?? snapshot?.availableBytes ?? 0
        quittingIDs = Set(targets.map(\.id))

        var asked: [(target: RunningAppMemory, app: NSRunningApplication)] = []
        var refused: [String] = []
        for target in targets {
            // Re-resolve by pid, and make sure the pid still belongs to the same
            // app: a pid can be reused after an app quits on its own.
            guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated,
                  app.bundleIdentifier == target.bundleIdentifier,
                  app.bundleURL == target.bundleURL,
                  app.launchDate == target.launchDate else { continue }
            // `terminate()` is the same request ⌘Q sends: the app saves, asks
            // about unsaved work, or refuses. Nothing is ever force quit.
            if app.terminate() {
                asked.append((target, app))
            } else {
                refused.append(target.name)
            }
        }

        let deadline = Date().addingTimeInterval(relaunch ? 15 : 6)
        while Date() < deadline, asked.contains(where: { !$0.app.isTerminated }) {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        let closed = asked.filter { $0.app.isTerminated }.map { $0.target }
        let stillOpen = asked.filter { !$0.app.isTerminated }.map { $0.target.name } + refused

        if relaunch {
            for app in closed { if let url = app.bundleURL { Self.open(url) } }
        }

        // Give the kernel a moment to reclaim the pages before measuring.
        if !closed.isEmpty { try? await Task.sleep(nanoseconds: 700_000_000) }
        let after = monitor.snapshot()
        if let after {
            snapshot = after
            recordUsage(after)
        }

        quittingIDs = []
        selection.subtract(closed.map(\.id))
        receipt = MemoryQuitReceipt(
            quit: closed.map { MemoryQuitReceipt.QuitApp(id: $0.id, name: $0.name, bundleURL: $0.bundleURL, bytes: $0.footprintBytes) },
            stillOpen: stillOpen,
            availableBefore: before,
            availableAfter: after?.availableBytes ?? before,
            isRelaunch: relaunch
        )
        if !relaunch && closed.contains(where: { $0.bundleURL != nil }) {
            reopenDeadline = Date().addingTimeInterval(Self.reopenWindow)
            reopenTask?.cancel()
            reopenTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.reopenWindow * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finalizeReopen()
            }
        }
        await refreshApps()
    }

    /// Open every app the last quit closed, in the background, the way they were.
    func reopenQuitApps() {
        guard let receipt, reopenDeadline != nil else { return }
        reopenTask?.cancel()
        reopenDeadline = nil
        for app in receipt.quit {
            if let url = app.bundleURL { Self.open(url) }
        }
        self.receipt = nil
        Task { [weak self] in
            // Let them start before re-listing.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await self?.refreshApps()
        }
    }

    /// Close the Reopen window; the receipt stays until dismissed.
    private func finalizeReopen() {
        reopenTask?.cancel()
        reopenDeadline = nil
    }

    func dismissReceipt() {
        guard reopenDeadline == nil else { return }
        receipt = nil
    }

    private static func open(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
    }

    // MARK: - Alerts

    private func trackPressure(_ snapshot: MemorySnapshot) {
        let now = snapshot.sampledAt
        elevatedSince = snapshot.pressure >= .warning ? (elevatedSince ?? now) : nil
        criticalSince = snapshot.pressure == .critical ? (criticalSince ?? now) : nil

        let settings = AppSettings.shared
        guard settings.memoryAlertsEnabled, settings.hasSeenWelcome else { return }
        let lastAlert = UserDefaults.standard.object(forKey: Self.lastAlertKey) as? Date
        guard MemoryAlertPolicy.shouldAlert(
            pressure: snapshot.pressure,
            elevatedSince: elevatedSince,
            criticalSince: criticalSince,
            lastAlertAt: lastAlert,
            now: now
        ) else { return }
        UserDefaults.standard.set(now, forKey: Self.lastAlertKey)
        Task { [weak self] in
            guard let self else { return }
            await self.refreshApps()
            let top = self.apps.filter { !$0.isFrontmost }.prefix(2)
            MemoryPressureNotifier.notify(
                appNames: top.map(\.name),
                bytes: top.reduce(0) { $0 + $1.footprintBytes },
                critical: snapshot.pressure == .critical
            )
        }
    }

    // MARK: - Snapshots

    #if DEBUG
    /// Fixture data for the rendered panel snapshots. Never persists anything.
    func showForSnapshot(
        snapshot: MemorySnapshot,
        apps: [RunningAppMemory],
        background: [AppMemoryUsage],
        suggested: Set<String>,
        growth: [String: MemoryGrowth],
        history: [MemoryUsagePoint],
        receipt: MemoryQuitReceipt? = nil,
        reopenDeadline: Date? = nil
    ) {
        self.snapshot = snapshot
        self.apps = apps
        self.backgroundProcesses = background
        self.suggestedIDs = suggested
        self.selection = suggested
        self.growth = growth
        self.usageHistory = history
        self.receipt = receipt
        self.reopenDeadline = reopenDeadline
        self.hasLoadedApps = true
    }
    #endif
}
