#if DEBUG
import SwiftUI
import AppKit
import CleanerEngine

/// Renders every state of the panel to PNG files from fixture data, then the
/// app quits. Debug builds only: `Dusty --render-snapshots <dir>`. CI runs it
/// on every change to the app so a reviewer can see what a change looks like
/// without building it.
///
/// Nothing here scans, cleans, or persists: the models are inert, the stats are
/// shown without being written, and the one setting it flips (the welcome flag)
/// is put back before it returns.
@MainActor
enum SnapshotRenderer {
    enum Shot: String, CaseIterable {
        case welcome, home, scanning, level, confirm, cleaned, settings
    }

    private static let panelSize = CGSize(width: DustyTheme.panelWidth, height: DustyTheme.panelHeight)
    private static let scale: CGFloat = 2

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
                let panel = MainPanelView(viewModel: model, settings: settings, updater: updater)
                // The level screen highlights the target an insight pointed at, then
                // fades the highlight; wait it out so the shot shows the resting state.
                let settle: UInt64 = scene == .level ? 3_000_000_000 : 1_200_000_000
                guard let rep = await render(panel, appearance: appearanceName, settle: settle) else {
                    print("snapshot: failed to render \(scene.rawValue)-\(suffix)")
                    continue
                }
                rendered[scene] = rep
                write(rep, to: directory.appendingPathComponent("\(scene.rawValue)-\(suffix).png"))
            }

            let tour: [Shot] = [.home, .level, .confirm, .settings]
            let reps = tour.compactMap { rendered[$0] }
            if reps.count == tour.count {
                composite(reps, dark: appearanceName == .darkAqua,
                          to: directory.appendingPathComponent("overview-\(suffix).png"))
            }
            if let home = rendered[.home] {
                composite([home], dark: appearanceName == .darkAqua,
                          to: directory.appendingPathComponent("framed-home-\(suffix).png"))
            }
        }

        settings.hasSeenWelcome = hadSeenWelcome
        print("snapshot: wrote \(directory.path)")
    }

    // MARK: - Rendering

    /// Hosts the view in an offscreen window (so AppKit-backed controls such as
    /// switches and pickers draw for real), lets it settle, then captures it at 2x.
    private static func render<V: View>(_ view: V, appearance name: NSAppearance.Name, settle: UInt64) async -> NSBitmapImageRep? {
        guard let appearance = NSAppearance(named: name) else { return nil }
        let root = view.environment(\.colorScheme, name == .darkAqua ? .dark : .light)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: panelSize)
        hosting.appearance = appearance

        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -6000, y: -6000), size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = hosting
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        try? await Task.sleep(nanoseconds: settle)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(panelSize.width * scale),
            pixelsHigh: Int(panelSize.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = panelSize
        appearance.performAsCurrentDrawingAppearance {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
        }
        return rep
    }

    private static func write(_ rep: NSBitmapImageRep, to url: URL) {
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    /// Panels side by side on a soft brand backdrop, with rounded corners and a
    /// window shadow, the way they look over a desktop.
    private static func composite(_ reps: [NSBitmapImageRep], dark: Bool, to url: URL) {
        let margin: CGFloat = 56
        let gap: CGFloat = 36
        let count = CGFloat(reps.count)
        let canvas = CGSize(width: margin * 2 + count * panelSize.width + (count - 1) * gap,
                            height: margin * 2 + panelSize.height)
        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvas.width * scale),
            pixelsHigh: Int(canvas.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        out.size = canvas
        guard let context = NSGraphicsContext(bitmapImageRep: out) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        let colors: [NSColor] = dark
            ? [NSColor(hex: 0x0B1026), NSColor(hex: 0x172554), NSColor(hex: 0x2E1065)]
            : [NSColor(hex: 0xE0F2FE), NSColor(hex: 0xDBEAFE), NSColor(hex: 0xEDE9FE)]
        NSGradient(colors: colors)?.draw(in: NSRect(origin: .zero, size: canvas), angle: -30)

        for (index, rep) in reps.enumerated() {
            let rect = NSRect(x: margin + CGFloat(index) * (panelSize.width + gap), y: margin,
                              width: panelSize.width, height: panelSize.height)
            let shape = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 34
            shadow.shadowOffset = NSSize(width: 0, height: -12)
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

        NSGraphicsContext.restoreGraphicsState()
        write(out, to: url)
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
        let model = DustyViewModel(startsServices: false)
        model.freeSpaceBytes = freeBytes
        model.totalSpaceBytes = totalBytes

        switch scene {
        case .welcome:
            break
        case .scanning:
            model.isScanning = true
            model.scanProgress = ScanProgress(completed: 23, total: 61, currentTargetName: "Xcode DerivedData")
        case .home, .level, .confirm, .cleaned, .settings:
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
        case .cleaned:
            let freed = 9 * gb + 610 * mb
            model.lastDeletionResult = DeletionResult(
                entries: [DeletionEntry(path: "~/Library/Caches/com.spotify.client", bytes: freed,
                                        movedToTrash: true, dryRun: false, trashedPath: "/tmp/x", targetID: "user-caches")],
                bytesFreed: freed,
                skippedPaths: [],
                freeSpaceBefore: freeBytes,
                freeSpaceAfter: freeBytes + freed
            )
            model.freeSpaceBytes = freeBytes + freed
            model.bannerStyle = .undoable
            model.canUndo = true
            model.undoDeadline = Date().addingTimeInterval(6)
        case .settings:
            model.route = .settings
        default:
            break
        }
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

    static func scan() -> FullScanResult {
        let safe = level(.safe, [
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
