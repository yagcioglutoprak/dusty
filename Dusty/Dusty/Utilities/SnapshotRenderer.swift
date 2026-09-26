#if DEBUG
import SwiftUI
import AppKit
import CleanerEngine

/// Renders every state of the panel to PNG files from fixture data, plus the
/// frames of the README's demo animation, then the app quits. Debug builds
/// only: `Dusty --render-snapshots <dir>`. CI runs it on every change to the
/// app so a reviewer can see what a change looks like without building it.
///
/// Nothing here scans, cleans, or persists: the models are inert, the stats are
/// shown without being written, and the one setting it flips (the welcome flag)
/// is put back before it returns.
@MainActor
enum SnapshotRenderer {
    enum Shot: String, CaseIterable {
        case welcome, home, scanning, level, confirm, cleaned, settings, memory, memoryConfirm, memoryRelaunch, memoryFreed,
             memoryCards
    }

    static let panelSize = CGSize(width: DustyTheme.panelWidth, height: DustyTheme.panelHeight)
    static let scale: CGFloat = 2

    static func renderAll(to directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = AppSettings.shared
        let hadSeenWelcome = settings.hasSeenWelcome
        let updater = Updater(startingUpdater: false)
        SnapshotFixtures.installStats()

        let appearances: [(NSAppearance.Name, String)] = [(NSAppearance.Name.darkAqua, "dark"), (NSAppearance.Name.aqua, "light")]
        for (appearanceName, suffix) in appearances {
            var rendered: [Shot: NSBitmapImageRep] = [:]
            for scene in Shot.allCases {
                settings.hasSeenWelcome = scene != .welcome
                let model = SnapshotFixtures.model(for: scene)
                let memory = SnapshotFixtures.memory(for: scene)
                let stage = scene == .memoryCards
                    ? Stage(MemoryCardSheet(), appearance: appearanceName)
                    : Stage(MainPanelView(viewModel: model, settings: settings, updater: updater, memory: memory),
                            appearance: appearanceName)
                // The level screen highlights the target an insight pointed at, then
                // fades the highlight; wait it out so the shot shows the resting state.
                try? await Task.sleep(nanoseconds: scene == .level ? 3_000_000_000 : 1_200_000_000)
                let captured = stage.capture()
                stage.close()
                guard let rep = captured else {
                    print("snapshot: failed to render \(scene.rawValue)-\(suffix)")
                    continue
                }
                rendered[scene] = rep
                write(rep, to: directory.appendingPathComponent("\(scene.rawValue)-\(suffix).png"))
            }

            let dark = appearanceName == .darkAqua
            let tour: [Shot] = [.home, .level, .confirm, .settings]
            let reps = tour.compactMap { rendered[$0] }
            if reps.count == tour.count, let overview = composite(reps, dark: dark, margin: 56) {
                write(overview, to: directory.appendingPathComponent("overview-\(suffix).png"))
            }
            if let home = rendered[.home], let framed = composite([home], dark: dark, margin: 56) {
                write(framed, to: directory.appendingPathComponent("framed-home-\(suffix).png"))
            }
        }

        await renderDemo(to: directory.appendingPathComponent("demo-frames", isDirectory: true),
                         settings: settings, updater: updater)

        settings.hasSeenWelcome = hadSeenWelcome
        print("snapshot: wrote \(directory.path)")
    }

    // MARK: - Demo animation

    /// The README demo: first run, a scan filling up, the results, a Safe clean
    /// with its undo ring emptying, then a level up close. Written as numbered
    /// PNG frames at 20 fps for gifski. Screen changes are composited here
    /// rather than captured mid-animation, so every frame is deterministic.
    private static func renderDemo(to directory: URL, settings: AppSettings, updater: Updater) async {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let reel = Reel(directory: directory)
        let appearance = NSAppearance.Name.darkAqua

        let memory = SnapshotFixtures.memory(for: .home)
        func stage(_ model: DustyViewModel, welcome: Bool = false) -> Stage {
            settings.hasSeenWelcome = !welcome
            return Stage(MainPanelView(viewModel: model, settings: settings, updater: updater, memory: memory),
                         appearance: appearance)
        }

        func still(_ model: DustyViewModel, welcome: Bool = false, settle: UInt64 = 900_000_000) async -> NSBitmapImageRep? {
            let shot = stage(model, welcome: welcome)
            try? await Task.sleep(nanoseconds: settle)
            let rep = shot.capture()
            shot.close()
            return rep
        }

        // 1. First run.
        guard let welcome = await still(SnapshotFixtures.model(for: .welcome), welcome: true, settle: 1_500_000_000) else { return }
        reel.hold(welcome, frames: 28)

        // 2. The first scan, one target at a time.
        let scanning = SnapshotFixtures.model(for: .scanning)
        let names = CleanupTargetRegistry.all.map(\.localizedName)
        let scanStage = stage(scanning)
        var scanFrames: [NSBitmapImageRep] = []
        let steps = 16
        for step in 0..<steps {
            let done = min(names.count, Int((Double(step) / Double(steps - 1) * Double(names.count)).rounded()))
            scanning.scanProgress = ScanProgress(completed: done, total: names.count,
                                                 currentTargetName: names[min(done, names.count - 1)])
            try? await Task.sleep(nanoseconds: step == 0 ? 1_000_000_000 : 300_000_000)
            if let rep = scanStage.capture() { scanFrames.append(rep) }
        }
        scanStage.close()
        guard let firstScan = scanFrames.first, let lastScan = scanFrames.last else { return }
        reel.transition(from: welcome, to: firstScan, frames: 8, style: .crossfade)
        for frame in scanFrames { reel.hold(frame, frames: 2) }

        // 3. What it found.
        guard let home = await still(SnapshotFixtures.model(for: .home)) else { return }
        reel.transition(from: lastScan, to: home, frames: 8, style: .crossfade)
        reel.hold(home, frames: 36)

        // 4. Clean Safe asks first.
        guard let confirm = await still(SnapshotFixtures.model(for: .confirm)) else { return }
        reel.transition(from: home, to: confirm, frames: 7, style: .crossfade)
        reel.hold(confirm, frames: 30)

        // 5. Cleaned, with the undo ring emptying in real time.
        let cleaned = SnapshotFixtures.cleanedModel()
        let cleanedStage = stage(cleaned)
        try? await Task.sleep(nanoseconds: 800_000_000)
        cleaned.undoDeadline = Date().addingTimeInterval(DustyViewModel.undoWindow)
        var ringFrames: [NSBitmapImageRep] = []
        for _ in 0..<14 {
            try? await Task.sleep(nanoseconds: 220_000_000)
            if let rep = cleanedStage.capture() { ringFrames.append(rep) }
        }
        cleanedStage.close()
        guard let firstRing = ringFrames.first, let lastRing = ringFrames.last else { return }
        reel.transition(from: confirm, to: firstRing, frames: 7, style: .crossfade)
        for frame in ringFrames { reel.hold(frame, frames: 3) }

        // 6. A level up close, then back to the start.
        guard let level = await still(SnapshotFixtures.levelAfterClean(), settle: 3_000_000_000) else { return }
        reel.transition(from: lastRing, to: level, frames: 9, style: .push)
        reel.hold(level, frames: 40)
        reel.transition(from: level, to: welcome, frames: 10, style: .crossfade)

        print("snapshot: demo has \(reel.count) frames")
    }

    // MARK: - Drawing

    static func write(_ rep: NSBitmapImageRep, to url: URL) {
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    /// A blank 2x bitmap of `size` points with `body` drawn into it.
    fileprivate static func draw(size: CGSize, _ body: () -> Void) -> NSBitmapImageRep? {
        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        out.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: out) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        body()
        NSGraphicsContext.restoreGraphicsState()
        return out
    }

    /// Panels side by side on a soft brand backdrop, with rounded corners and a
    /// window shadow, the way they look over a desktop.
    fileprivate static func composite(_ reps: [NSBitmapImageRep], dark: Bool, margin: CGFloat,
                                      solidBackground: NSColor? = nil) -> NSBitmapImageRep? {
        let gap: CGFloat = 36
        let count = CGFloat(reps.count)
        let canvas = CGSize(width: margin * 2 + count * panelSize.width + (count - 1) * gap,
                            height: margin * 2 + panelSize.height)
        return draw(size: canvas) {
            let bounds = NSRect(origin: .zero, size: canvas)
            if let solidBackground {
                solidBackground.setFill()
                bounds.fill()
            } else {
                let colors: [NSColor] = dark
                    ? [NSColor(hex: 0x0B1026), NSColor(hex: 0x172554), NSColor(hex: 0x2E1065)]
                    : [NSColor(hex: 0xE0F2FE), NSColor(hex: 0xDBEAFE), NSColor(hex: 0xEDE9FE)]
                NSGradient(colors: colors)?.draw(in: bounds, angle: -30)
            }

            for (index, rep) in reps.enumerated() {
                let rect = NSRect(x: margin + CGFloat(index) * (panelSize.width + gap), y: margin,
                                  width: panelSize.width, height: panelSize.height)
                let shape = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)

                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowBlurRadius = min(34, margin * 0.8)
                shadow.shadowOffset = NSSize(width: 0, height: -min(12, margin * 0.3))
                shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.22)
                shadow.set()
                NSColor.black.setFill()
                shape.fill()
                NSGraphicsContext.restoreGraphicsState()

                NSGraphicsContext.saveGraphicsState()
                shape.addClip()
                rep.draw(in: rect)
                NSGraphicsContext.restoreGraphicsState()

                NSColor(white: dark ? 1 : 0, alpha: dark ? 0.14 : 0.10).setStroke()
                shape.lineWidth = 1
                shape.stroke()
            }
        }
    }

    /// One demo frame: the panel with rounded corners on a flat dark ground
    /// (flat, because a gradient bands badly in a 256-color GIF).
    fileprivate static func poster(_ rep: NSBitmapImageRep) -> NSBitmapImageRep? {
        composite([rep], dark: true, margin: 22, solidBackground: NSColor(hex: 0x0D1222))
    }

    /// The in-between frame of a screen change at progress `t` (0...1).
    fileprivate static func mix(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, t: CGFloat, style: Reel.Style) -> NSBitmapImageRep? {
        // Ease in and out, like the panel's own springs.
        let u = -2 * t + 2
        let e = t < 0.5 ? 2 * t * t : 1 - u * u / 2
        let rect = NSRect(origin: .zero, size: panelSize)
        return draw(size: panelSize) {
            NSColor(hex: 0x111215).setFill()
            rect.fill()
            switch style {
            case .crossfade:
                a.draw(in: rect)
                b.draw(in: rect, from: .zero, operation: .sourceOver, fraction: e, respectFlipped: false, hints: nil)
            case .push:
                a.draw(in: rect.offsetBy(dx: -e * rect.width * 0.3, dy: 0), from: .zero, operation: .sourceOver,
                       fraction: 1 - 0.6 * e, respectFlipped: false, hints: nil)
                b.draw(in: rect.offsetBy(dx: (1 - e) * rect.width, dy: 0), from: .zero, operation: .sourceOver,
                       fraction: 1, respectFlipped: false, hints: nil)
            }
        }
    }
}

/// The home screen's memory pieces in every state, stacked on one canvas: the
/// top-bar pill and the card with idle apps to free, calm, under pressure, and
/// still reading. The home shot itself only shows the card's header.
private struct MemoryCardSheet: View {
    var body: some View {
        ZStack(alignment: .top) {
            DustyTheme.canvas
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    MemoryPill(memory: SnapshotFixtures.memory(for: .home), onOpen: {})
                    MemoryPill(memory: SnapshotFixtures.memory(for: .home, pressure: .normal, suggestions: false), onOpen: {})
                    MemoryPill(memory: SnapshotFixtures.memory(for: .home, pressure: .critical, suggestions: false), onOpen: {})
                }
                MemoryCard(memory: SnapshotFixtures.memory(for: .home), onOpen: {})
                MemoryCard(memory: SnapshotFixtures.memory(for: .home, pressure: .normal, suggestions: false), onOpen: {})
                MemoryCard(memory: SnapshotFixtures.memory(for: .home, pressure: .critical, suggestions: false), onOpen: {})
                MemoryCard(memory: MemoryModel(startsServices: false), onOpen: {})
            }
            .padding(.horizontal, DustyTheme.gutter)
            .padding(.vertical, 18)
        }
        .frame(width: DustyTheme.panelWidth, height: DustyTheme.panelHeight)
    }
}

/// An offscreen window hosting one panel, so AppKit-backed controls (switches,
/// pickers) draw for real, and a way to capture it at 2x.
@MainActor
private final class Stage {
    private let appearance: NSAppearance
    private let hosting: NSView
    private let window: NSWindow

    init<V: View>(_ view: V, appearance name: NSAppearance.Name) {
        let size = SnapshotRenderer.panelSize
        let appearance = NSAppearance(named: name) ?? NSAppearance(named: .darkAqua)!
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, name == .darkAqua ? .dark : .light))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.appearance = appearance
        self.appearance = appearance
        self.hosting = hosting
        self.window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -6000, y: -6000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = hosting
        window.orderFrontRegardless()
    }

    func capture() -> NSBitmapImageRep? {
        hosting.layoutSubtreeIfNeeded()
        let size = SnapshotRenderer.panelSize
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * SnapshotRenderer.scale),
            pixelsHigh: Int(size.height * SnapshotRenderer.scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        let hosting = self.hosting
        appearance.performAsCurrentDrawingAppearance {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
        }
        return rep
    }

    func close() {
        window.orderOut(nil)
        window.contentView = nil
    }
}

/// Numbered demo frames on disk, each framed as a poster.
@MainActor
private final class Reel {
    enum Style { case crossfade, push }

    private let directory: URL
    private(set) var count = 0

    init(directory: URL) {
        self.directory = directory
    }

    func hold(_ rep: NSBitmapImageRep, frames: Int) {
        guard let data = SnapshotRenderer.poster(rep)?.representation(using: .png, properties: [:]) else { return }
        for _ in 0..<frames { append(data) }
    }

    func transition(from a: NSBitmapImageRep, to b: NSBitmapImageRep, frames: Int, style: Style) {
        guard frames > 0 else { return }
        for i in 1...frames {
            let t = CGFloat(i) / CGFloat(frames + 1)
            guard let mixed = SnapshotRenderer.mix(a, b, t: t, style: style),
                  let data = SnapshotRenderer.poster(mixed)?.representation(using: .png, properties: [:]) else { continue }
            append(data)
        }
    }

    private func append(_ data: Data) {
        count += 1
        try? data.write(to: directory.appendingPathComponent(String(format: "%04d.png", count)))
    }
}

// MARK: - Fixtures

/// A believable developer Mac: a disk getting full, gigabytes of caches, build
/// data, and a couple of forgotten installers.
@MainActor
private enum SnapshotFixtures {
    static let gb: Int64 = 1_073_741_824
    static let mb: Int64 = 1_048_576
    static let totalBytes: Int64 = 494_384_795_648
    static let freeBytes: Int64 = 86 * gb + 420 * mb

    static func installStats() {
        let now = Date()
        CleanStatsStore.shared.showForSnapshot(
            lifetimeBytes: 412 * gb + 300 * mb,
            cleanCount: 37,
            firstCleanAt: now.addingTimeInterval(-86400 * 160),
            recent: [
                CleanRecord(date: now.addingTimeInterval(-3600 * 20), level: 1, bytes: 9 * gb + 610 * mb, items: 41),
                CleanRecord(date: now.addingTimeInterval(-86400 * 3), level: 2, bytes: 14 * gb + 200 * mb, items: 12),
                CleanRecord(date: now.addingTimeInterval(-86400 * 9), level: 1, bytes: 6 * gb + 80 * mb, items: 33),
                CleanRecord(date: now.addingTimeInterval(-86400 * 16), level: 3, bytes: 3 * gb + 700 * mb, items: 2)
            ]
        )
    }

    static func model(for scene: SnapshotRenderer.Shot) -> DustyViewModel {
        if scene == .cleaned { return cleanedModel() }
        let model = DustyViewModel(startsServices: false)
        model.freeSpaceBytes = freeBytes
        model.totalSpaceBytes = totalBytes

        switch scene {
        case .welcome:
            break
        case .scanning:
            model.isScanning = true
            model.scanProgress = ScanProgress(completed: 23, total: 61, currentTargetName: "Xcode DerivedData")
        case .home, .level, .confirm, .cleaned, .settings, .memory, .memoryConfirm, .memoryRelaunch, .memoryFreed,
             .memoryCards:
            model.scanResult = scan()
            model.hasScannedOnce = true
            model.advisories = advisories
            model.diskForecast = DiskForecast(consumedBytesPerDay: 2 * gb + 200 * mb, daysUntilFull: 39)
        }

        switch scene {
        case .level:
            model.route = .level(.developer)
            model.focusedTargetID = "xcode-derived-data"
        case .confirm:
            model.pendingConfirmationLevel = .safe
        case .settings:
            model.route = .settings
        case .memory, .memoryConfirm, .memoryRelaunch, .memoryFreed:
            model.route = .memory
        default:
            break
        }
        return model
    }

    // MARK: Memory

    /// A 16 GB Mac under some pressure: Xcode in front, a Chrome that has been
    /// growing all afternoon, and three apps nobody has touched in hours.
    static func memory(
        for scene: SnapshotRenderer.Shot,
        pressure: MemoryPressure = .warning,
        suggestions: Bool = true
    ) -> MemoryModel {
        let memory = MemoryModel(startsServices: false)
        guard scene != .welcome else { return memory }
        let now = Date()
        let snapshot = MemorySnapshot(
            totalBytes: 16 * gb,
            appBytes: 7 * gb + 310 * mb,
            wiredBytes: 2 * gb + 620 * mb,
            compressedBytes: 2 * gb + 150 * mb,
            cachedFilesBytes: 2 * gb + 900 * mb,
            swapUsedBytes: pressure == .normal ? 0 : 1 * gb + 380 * mb,
            swapTotalBytes: 3 * gb,
            pressure: pressure,
            sampledAt: now
        )
        let hour: TimeInterval = 3600
        let apps = [
            memoryApp("Xcode", "/Applications/Xcode.app", "com.apple.dt.Xcode", 2 * gb + 940 * mb, processes: 6,
                      frontmost: true, lastUsed: nil, now: now),
            memoryApp("Google Chrome", "/Applications/Google Chrome.app", "com.google.Chrome", 2 * gb + 610 * mb,
                      processes: 24, lastUsed: now.addingTimeInterval(-0.4 * hour), now: now),
            memoryApp("Photos", "/System/Applications/Photos.app", "com.apple.Photos", 1 * gb + 330 * mb, processes: 3,
                      lastUsed: now.addingTimeInterval(-3.2 * hour), now: now),
            memoryApp("Safari", "/Applications/Safari.app", "com.apple.Safari", 830 * mb, processes: 9,
                      lastUsed: now.addingTimeInterval(-0.2 * hour), now: now),
            memoryApp("Maps", "/System/Applications/Maps.app", "com.apple.Maps", 720 * mb, processes: 2,
                      lastUsed: now.addingTimeInterval(-2.1 * hour), now: now),
            memoryApp("Music", "/System/Applications/Music.app", "com.apple.Music", 540 * mb, processes: 2,
                      lastUsed: now.addingTimeInterval(-1.5 * hour), audio: true, now: now),
            memoryApp("Notes", "/System/Applications/Notes.app", "com.apple.Notes", 330 * mb, processes: 1,
                      lastUsed: now.addingTimeInterval(-5 * hour), now: now),
            memoryApp("Mail", "/System/Applications/Mail.app", "com.apple.mail", 260 * mb, processes: 2,
                      lastUsed: now.addingTimeInterval(-0.7 * hour), now: now),
            memoryApp("Preview", "/System/Applications/Preview.app", "com.apple.Preview", 150 * mb, processes: 1,
                      lastUsed: nil, now: now),
        ]
        let suggested: Set<String> = suggestions
            ? ["/System/Applications/Photos.app", "/System/Applications/Maps.app", "/System/Applications/Notes.app"]
            : []
        let background = [
            AppMemoryUsage(id: "/opt/homebrew/bin/node", name: "node", bundlePath: nil, leaderPID: 4410,
                           pids: [4410, 4411, 4415], footprintBytes: 1 * gb + 120 * mb),
            AppMemoryUsage(id: "/opt/homebrew/opt/postgresql@16/bin/postgres", name: "postgres", bundlePath: nil,
                           leaderPID: 812, pids: [812, 813, 814, 815], footprintBytes: 410 * mb),
        ]
        // A slow climb over the hour, with a little noise.
        let history = (0..<60).map { minute -> MemoryUsagePoint in
            let t = Double(minute) / 59
            let fraction = 0.66 + 0.09 * t + 0.012 * sin(Double(minute) * 0.9)
            return MemoryUsagePoint(date: now.addingTimeInterval(-Double(59 - minute) * 60),
                                    usedFraction: fraction, pressure: t > 0.7 ? .warning : .normal)
        }
        memory.showForSnapshot(
            snapshot: snapshot,
            apps: apps,
            background: background,
            suggested: suggested,
            growth: ["/Applications/Google Chrome.app": MemoryGrowth(fromBytes: 1 * gb + 280 * mb,
                                                                     toBytes: 2 * gb + 610 * mb,
                                                                     since: now.addingTimeInterval(-3 * hour))],
            history: history
        )
        switch scene {
        case .memoryConfirm:
            memory.pendingQuit = apps.filter { suggested.contains($0.id) }
        case .memoryRelaunch:
            memory.pendingRelaunch = apps.first { $0.name == "Google Chrome" }
        case .memoryFreed:
            let quit = apps.filter { suggested.contains($0.id) }
            let freed = quit.reduce(Int64(0)) { $0 + $1.footprintBytes }
            memory.showForSnapshot(
                snapshot: snapshot,
                apps: apps.filter { !suggested.contains($0.id) },
                background: background,
                suggested: [],
                growth: ["/Applications/Google Chrome.app": MemoryGrowth(fromBytes: 1 * gb + 280 * mb,
                                                                         toBytes: 2 * gb + 610 * mb,
                                                                         since: now.addingTimeInterval(-3 * hour))],
                history: history,
                receipt: MemoryQuitReceipt(
                    quit: quit.map { MemoryQuitReceipt.QuitApp(id: $0.id, name: $0.name, bundleURL: $0.bundleURL,
                                                               bytes: $0.footprintBytes) },
                    stillOpen: [],
                    availableBefore: snapshot.availableBytes,
                    availableAfter: snapshot.availableBytes + freed,
                    isRelaunch: false
                ),
                reopenDeadline: now.addingTimeInterval(MemoryModel.reopenWindow)
            )
        default:
            break
        }
        return memory
    }

    private static func memoryApp(
        _ name: String, _ path: String, _ bundleID: String, _ bytes: Int64, processes: Int,
        frontmost: Bool = false, lastUsed: Date?, audio: Bool = false, now: Date
    ) -> RunningAppMemory {
        RunningAppMemory(
            id: path,
            name: name,
            bundleIdentifier: bundleID,
            bundleURL: URL(fileURLWithPath: path),
            pid: 0,
            launchDate: now.addingTimeInterval(-8 * 3600),
            footprintBytes: bytes,
            processCount: processes,
            icon: NSWorkspace.shared.icon(forFile: path),
            isFrontmost: frontmost,
            lastActiveAt: lastUsed,
            idleSince: frontmost ? now : (lastUsed ?? now.addingTimeInterval(-6 * 3600)),
            isPlayingAudio: audio,
            isUsingMicrophone: false
        )
    }

    /// Right after a Safe clean: the Safe level is empty, the space is back, and
    /// the receipt's undo window is open.
    static func cleanedModel() -> DustyViewModel {
        let model = levelAfterClean()
        let freed = scan().levelResults[.safe]?.totalBytes ?? 0
        model.route = .home
        model.focusedTargetID = nil
        model.lastDeletionResult = DeletionResult(
            entries: [DeletionEntry(path: "~/Library/Caches/com.spotify.client", bytes: freed,
                                    movedToTrash: true, dryRun: false, trashedPath: "/tmp/x", targetID: "user-caches")],
            bytesFreed: freed,
            skippedPaths: [],
            freeSpaceBefore: freeBytes,
            freeSpaceAfter: freeBytes + freed
        )
        model.bannerStyle = .undoable
        model.canUndo = true
        model.undoDeadline = Date().addingTimeInterval(DustyViewModel.undoWindow)
        return model
    }

    /// The Developer level after the Safe clean, opened from its insight.
    static func levelAfterClean() -> DustyViewModel {
        let model = DustyViewModel(startsServices: false)
        let freed = scan().levelResults[.safe]?.totalBytes ?? 0
        model.totalSpaceBytes = totalBytes
        model.freeSpaceBytes = freeBytes + freed
        model.scanResult = scan(safeCleaned: true)
        model.hasScannedOnce = true
        model.advisories = advisories
        model.diskForecast = DiskForecast(consumedBytesPerDay: 2 * gb + 200 * mb, daysUntilFull: 39)
        model.route = .level(.developer)
        model.focusedTargetID = "xcode-derived-data"
        return model
    }

    private static let advisories: [Advisory] = [
        Advisory(id: "orphan-unity-cache", title: "Unity cache left behind",
                 detail: "Unity does not appear to be installed anymore, but 4.2 GB of its data is still on disk.",
                 targetID: "unity-cache", bytes: 4 * gb + 200 * mb),
        Advisory(id: "stale-gradle-cache", title: "Gradle cache untouched for 142 days",
                 detail: "Nothing has written to this cache since May 3. 1.9 GB would regenerate only if something needs it.",
                 targetID: "gradle-cache", bytes: 1 * gb + 900 * mb)
    ]

    private static func registryTarget(_ id: String) -> CleanupTarget? {
        CleanupTargetRegistry.all.first { $0.id == id }
    }

    /// (display name, path under home, size, selected, days since last write)
    private typealias Item = (name: String, path: String, bytes: Int64, selected: Bool, age: Double)

    private static func result(_ id: String, _ items: [Item]) -> TargetScanResult? {
        guard let target = registryTarget(id) else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = items.map { item in
            ResolvedPath(
                id: "\(id)/\(item.name)",
                path: item.path.hasPrefix("~") ? home + item.path.dropFirst() : item.path,
                displayName: item.name,
                targetID: id,
                estimatedBytes: item.bytes,
                isSelected: item.selected,
                lastModified: Date().addingTimeInterval(-86400 * item.age)
            )
        }
        return TargetScanResult(target: target, resolvedPaths: paths)
    }

    private static func level(_ level: CleanupLevel, _ found: [TargetScanResult?]) -> LevelScanResult {
        let byID = Dictionary(uniqueKeysWithValues: found.compactMap { $0 }.map { ($0.id, $0) })
        let targets = CleanupTargetRegistry.targets(for: level).map { byID[$0.id] ?? TargetScanResult(target: $0, resolvedPaths: []) }
        return LevelScanResult(level: level, targetResults: targets)
    }

    static func scan(safeCleaned: Bool = false) -> FullScanResult {
        let safe = safeCleaned ? level(.safe, []) : level(.safe, [
            result("user-caches", [
                ("com.spotify.client", "~/Library/Caches/com.spotify.client", 2 * gb + 140 * mb, true, 1),
                ("Google", "~/Library/Caches/Google", 1 * gb + 410 * mb, true, 2),
                ("com.apple.Safari", "~/Library/Caches/com.apple.Safari", 820 * mb, true, 0.5),
                ("com.microsoft.VSCode.ShipIt", "~/Library/Caches/com.microsoft.VSCode.ShipIt", 640 * mb, true, 45),
                ("org.swift.swiftpm", "~/Library/Caches/org.swift.swiftpm", 512 * mb, true, 6),
                ("com.figma.Desktop", "~/Library/Caches/com.figma.Desktop", 388 * mb, true, 12)
            ]),
            result("empty-trash", [("Trash", "~/.Trash", 3 * gb + 250 * mb, true, 4)]),
            result("chrome-cache", [("Default", "~/Library/Caches/Google/Chrome/Default", 1 * gb + 120 * mb, true, 0.2)]),
            result("slack-cache", [("Cache", "~/Library/Application Support/Slack/Cache", 780 * mb, true, 0.1)]),
            result("user-logs", [("DiagnosticReports", "~/Library/Logs/DiagnosticReports", 312 * mb, true, 3)]),
            result("discord-cache", [("Cache", "~/Library/Application Support/discord/Cache", 394 * mb, true, 1)])
        ])
        let developer = level(.developer, [
            result("xcode-derived-data", [
                ("Dusty-bqzvhxkcgmqoaf", "~/Library/Developer/Xcode/DerivedData/Dusty-bqzvhxkcgmqoaf", 4 * gb + 820 * mb, true, 0.3),
                ("Atlas-gyrfdtkeowmzqb", "~/Library/Developer/Xcode/DerivedData/Atlas-gyrfdtkeowmzqb", 2 * gb + 310 * mb, true, 38),
                ("Playground-cdxhwnbq", "~/Library/Developer/Xcode/DerivedData/Playground-cdxhwnbq", 1 * gb + 90 * mb, true, 96)
            ]),
            result("xcode-device-support", [
                ("iPhone15,2 17.5 (21F79)", "~/Library/Developer/Xcode/iOS DeviceSupport/iPhone15,2 17.5 (21F79)", 3 * gb + 410 * mb, true, 140),
                ("iPhone16,1 18.1 (22B83)", "~/Library/Developer/Xcode/iOS DeviceSupport/iPhone16,1 18.1 (22B83)", 3 * gb + 900 * mb, false, 20)
            ]),
            result("npm-cache", [("_cacache", "~/.npm/_cacache", 2 * gb + 380 * mb, true, 2)]),
            result("homebrew-cache", [("Homebrew", "~/Library/Caches/Homebrew", 1 * gb + 940 * mb, true, 8)]),
            result("cargo-cache", [("registry", "~/.cargo/registry", 1 * gb + 210 * mb, true, 15)]),
            result("gradle-cache", [("caches", "~/.gradle/caches", 1 * gb + 900 * mb, true, 142)]),
            result("pip-cache", [("pip", "~/Library/Caches/pip", 540 * mb, true, 22)]),
            result("unity-cache", [("Unity", "~/Library/Unity/cache", 4 * gb + 200 * mb, false, 300)]),
            result("docker-prune", [("All unused images, build cache & stopped containers", "docker:system prune", 6 * gb + 200 * mb, false, 0)])
        ])
        let deep = level(.deep, [
            result("downloads-installers", [
                ("Xcode_16.1.xip", "~/Downloads/Xcode_16.1.xip", 3 * gb + 90 * mb, false, 70),
                ("Docker.dmg", "~/Downloads/Docker.dmg", 610 * mb, false, 120)
            ]),
            result("stale-project-artifacts", [
                ("landing-page/node_modules", "~/Code/landing-page/node_modules", 1 * gb + 310 * mb, false, 210)
            ]),
            result("xcode-archives", [
                ("Dusty 1.6.0", "~/Library/Developer/Xcode/Archives/2026-05-02/Dusty 1.6.0.xcarchive", 380 * mb, false, 144)
            ])
        ])
        return FullScanResult(
            levelResults: [.safe: safe, .developer: developer, .deep: deep],
            scannedAt: Date().addingTimeInterval(-8 * 60)
        )
    }
}
#endif
