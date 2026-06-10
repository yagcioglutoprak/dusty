import Foundation

/// Central registry of all cleanup targets. One-line add/remove per target.
public enum CleanupTargetRegistry {
    public static let all: [CleanupTarget] = level1 + level2 + level3

    public static func targets(for level: CleanupLevel) -> [CleanupTarget] {
        all.filter { $0.level == level }
    }

    // MARK: - Level 1: Safe

    public static let level1: [CleanupTarget] = [
        CleanupTarget(
            id: "user-caches",
            displayName: "User Caches",
            level: .safe,
            pathTemplates: ["~/Library/Caches"],
            category: "Caches",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "user-logs",
            displayName: "App Logs",
            level: .safe,
            pathTemplates: ["~/Library/Logs"],
            category: "Logs",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "empty-trash",
            displayName: "Empty Trash",
            level: .safe,
            pathTemplates: ["~/.Trash"],
            category: "Trash",
            deletesContentsNotDirectory: true,
            regenerates: true,
            // Always permanent: the destination IS the Trash, so a trash-move is a no-op.
            bypassesTrash: true
        ),
        CleanupTarget(
            id: "safari-cache",
            displayName: "Safari Cache",
            level: .safe,
            pathTemplates: ["~/Library/Caches/com.apple.Safari"],
            category: "Browser",
            deletesContentsNotDirectory: true,
            regenerates: true,
            requiresAppClosed: "Safari",
            requiresAppBundleID: "com.apple.Safari"
        ),
        CleanupTarget(
            id: "chrome-cache",
            displayName: "Chrome Cache",
            level: .safe,
            pathTemplates: [
                "~/Library/Caches/Google/Chrome",
                "~/Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage"
            ],
            category: "Browser",
            deletesContentsNotDirectory: true,
            regenerates: true,
            requiresAppClosed: "Google Chrome",
            requiresAppBundleID: "com.google.Chrome"
        ),
        CleanupTarget(
            id: "brave-cache",
            displayName: "Brave Cache",
            level: .safe,
            pathTemplates: ["~/Library/Caches/BraveSoftware/Brave-Browser"],
            category: "Browser",
            deletesContentsNotDirectory: true,
            regenerates: true,
            requiresAppClosed: "Brave Browser",
            requiresAppBundleID: "com.brave.Browser"
        ),
        CleanupTarget(
            id: "arc-cache",
            displayName: "Arc Cache",
            level: .safe,
            pathTemplates: ["~/Library/Caches/Arc"],
            category: "Browser",
            deletesContentsNotDirectory: true,
            regenerates: true,
            requiresAppClosed: "Arc",
            requiresAppBundleID: "company.thebrowser.Browser"
        ),
        // App caches under Application Support that the blanket ~/Library/Caches sweep
        // misses. Only the named cache subfolders are listed: never the app's whole
        // Application Support folder, which holds real data.
        CleanupTarget(
            id: "discord-cache",
            displayName: "Discord Cache",
            level: .safe,
            pathTemplates: [
                "~/Library/Application Support/discord/Cache",
                "~/Library/Application Support/discord/Code Cache",
                "~/Library/Application Support/discord/GPUCache",
                "~/Library/Application Support/discord/DawnGraphiteCache",
                "~/Library/Application Support/discord/DawnWebGPUCache",
                "~/Library/Application Support/discord/Service Worker/CacheStorage"
            ],
            category: "App Cache",
            deletesContentsNotDirectory: true,
            regenerates: true,
            requiresAppClosed: "Discord",
            requiresAppBundleID: "com.hnc.Discord"
        ),
        CleanupTarget(
            id: "spotify-cache",
            displayName: "Spotify Cache",
            level: .safe,
            pathTemplates: ["~/Library/Application Support/Spotify/PersistentCache"],
            category: "App Cache",
            deletesContentsNotDirectory: true,
            regenerates: true,
            requiresAppClosed: "Spotify",
            requiresAppBundleID: "com.spotify.client"
        ),
        CleanupTarget(
            id: "vscode-cache",
            displayName: "VS Code Cache",
            level: .safe,
            pathTemplates: [
                "~/Library/Application Support/Code/Cache",
                "~/Library/Application Support/Code/Code Cache",
                "~/Library/Application Support/Code/GPUCache",
                "~/Library/Application Support/Code/DawnGraphiteCache",
                "~/Library/Application Support/Code/DawnWebGPUCache",
                "~/Library/Application Support/Code/CachedData"
            ],
            category: "App Cache",
            deletesContentsNotDirectory: true,
            regenerates: true,
            requiresAppClosed: "Code",
            requiresAppBundleID: "com.microsoft.VSCode"
        ),
        CleanupTarget(
            id: "slack-cache",
            displayName: "Slack Cache",
            level: .safe,
            pathTemplates: [
                "~/Library/Application Support/Slack/Cache",
                "~/Library/Application Support/Slack/Code Cache",
                "~/Library/Application Support/Slack/GPUCache",
                "~/Library/Application Support/Slack/DawnGraphiteCache",
                "~/Library/Application Support/Slack/DawnWebGPUCache",
                "~/Library/Application Support/Slack/Service Worker/CacheStorage"
            ],
            category: "App Cache",
            deletesContentsNotDirectory: true,
            regenerates: true,
            requiresAppClosed: "Slack",
            requiresAppBundleID: "com.tinyspeck.slackmacgap"
        ),
        CleanupTarget(
            id: "cursor-cache",
            displayName: "Cursor Cache",
            level: .safe,
            pathTemplates: [
                "~/Library/Application Support/Cursor/Cache",
                "~/Library/Application Support/Cursor/Code Cache",
                "~/Library/Application Support/Cursor/GPUCache",
                "~/Library/Application Support/Cursor/DawnGraphiteCache",
                "~/Library/Application Support/Cursor/DawnWebGPUCache",
                "~/Library/Application Support/Cursor/CachedData"
            ],
            category: "App Cache",
            deletesContentsNotDirectory: true,
            regenerates: true,
            requiresAppClosed: "Cursor",
            requiresAppBundleID: "com.todesktop.230313mzl4w4u92"
        ),
        CleanupTarget(
            id: "signal-cache",
            displayName: "Signal Cache",
            level: .safe,
            pathTemplates: [
                "~/Library/Application Support/Signal/Cache",
                "~/Library/Application Support/Signal/Code Cache",
                "~/Library/Application Support/Signal/GPUCache",
                "~/Library/Application Support/Signal/DawnGraphiteCache",
                "~/Library/Application Support/Signal/DawnWebGPUCache"
            ],
            category: "App Cache",
            deletesContentsNotDirectory: true,
            regenerates: true,
            requiresAppClosed: "Signal",
            requiresAppBundleID: "org.whispersystems.signal-desktop"
        ),
        CleanupTarget(
            id: "obsidian-cache",
            displayName: "Obsidian Cache",
            level: .safe,
            pathTemplates: [
                "~/Library/Application Support/obsidian/Cache",
                "~/Library/Application Support/obsidian/Code Cache",
                "~/Library/Application Support/obsidian/GPUCache",
                "~/Library/Application Support/obsidian/DawnGraphiteCache",
                "~/Library/Application Support/obsidian/DawnWebGPUCache"
            ],
            category: "App Cache",
            deletesContentsNotDirectory: true,
            regenerates: true,
            requiresAppClosed: "Obsidian",
            requiresAppBundleID: "md.obsidian"
        ),
        CleanupTarget(
            // New (sandboxed) Teams keeps its caches in the standard container
            // location, which the ~/Library/Caches sweep does not reach.
            id: "teams-cache",
            displayName: "Microsoft Teams Cache",
            level: .safe,
            pathTemplates: ["~/Library/Containers/com.microsoft.teams2/Data/Library/Caches"],
            category: "App Cache",
            deletesContentsNotDirectory: true,
            regenerates: true,
            requiresAppClosed: "Microsoft Teams",
            requiresAppBundleID: "com.microsoft.teams2"
        ),
        CleanupTarget(
            // Zoom keeps every downloaded update installer around. Only the
            // AutoUpdater folder is listed, never zoom.us itself (meeting data, settings).
            id: "zoom-updates",
            displayName: "Zoom Update Installers",
            level: .safe,
            pathTemplates: ["~/Library/Application Support/zoom.us/AutoUpdater"],
            category: "App Cache",
            deletesContentsNotDirectory: true,
            regenerates: true,
            requiresAppClosed: "zoom.us",
            requiresAppBundleID: "us.zoom.xos"
        ),
        CleanupTarget(
            // Media re-downloads from Telegram's cloud on demand. Resolved dynamically:
            // the App Store build keeps a per-account media cache inside its group
            // container, the telegram.org build uses fixed cache dirs under tdata.
            // Only those cache dirs are reachable, never chat databases or settings.
            id: "telegram-media-cache",
            displayName: "Telegram Media Cache",
            level: .safe,
            pathTemplates: [
                "~/Library/Application Support/Telegram Desktop/tdata/user_data/cache",
                "~/Library/Application Support/Telegram Desktop/tdata/user_data/media_cache"
            ],
            category: "App Cache",
            deletesContentsNotDirectory: true,
            regenerates: true,
            requiresAppClosed: "Telegram",
            requiresAppBundleID: "ru.keepcoder.Telegram",
            usesDynamicPaths: true
        ),
    ]

    // MARK: - Level 2: Developer

    public static let level2: [CleanupTarget] = [
        CleanupTarget(
            id: "xcode-derived-data",
            displayName: "Xcode DerivedData",
            level: .developer,
            pathTemplates: ["~/Library/Developer/Xcode/DerivedData"],
            category: "Xcode",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "xcode-device-support",
            displayName: "Old iOS DeviceSupport",
            level: .developer,
            pathTemplates: ["~/Library/Developer/Xcode/iOS DeviceSupport"],
            category: "Xcode",
            usesDynamicPaths: true
        ),
        CleanupTarget(
            id: "core-simulator-caches",
            displayName: "CoreSimulator Caches",
            level: .developer,
            pathTemplates: ["~/Library/Developer/CoreSimulator/Caches"],
            category: "Simulator",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "simulator-unavailable",
            displayName: "Unavailable Simulators",
            level: .developer,
            pathTemplates: [],
            category: "Simulator",
            action: .simctlDeleteUnavailable,
            usesDynamicPaths: true
        ),
        CleanupTarget(
            id: "npm-cache",
            displayName: "npm Cache",
            level: .developer,
            pathTemplates: ["~/.npm"],
            category: "Package Manager",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "yarn-cache",
            displayName: "Yarn Cache",
            level: .developer,
            pathTemplates: ["~/Library/Caches/Yarn", "~/.yarn/cache"],
            category: "Package Manager",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "pnpm-cache",
            displayName: "pnpm Store",
            level: .developer,
            pathTemplates: ["~/Library/pnpm/store"],
            category: "Package Manager",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "pip-cache",
            displayName: "pip Cache",
            level: .developer,
            pathTemplates: ["~/Library/Caches/pip"],
            category: "Package Manager",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "gradle-cache",
            displayName: "Gradle Cache",
            level: .developer,
            pathTemplates: ["~/.gradle/caches"],
            category: "Package Manager",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "cocoapods-cache",
            displayName: "CocoaPods Cache",
            level: .developer,
            pathTemplates: ["~/Library/Caches/CocoaPods"],
            category: "Package Manager",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "swiftpm-cache",
            displayName: "SwiftPM Cache",
            level: .developer,
            pathTemplates: ["~/Library/Caches/org.swift.swiftpm"],
            category: "Package Manager",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "cargo-cache",
            displayName: "Cargo Registry Cache",
            level: .developer,
            pathTemplates: ["~/.cargo/registry/cache", "~/.cargo/registry/index"],
            category: "Package Manager",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "go-cache",
            displayName: "Go Build & Module Cache",
            level: .developer,
            pathTemplates: ["~/Library/Caches/go-build", "~/go/pkg/mod/cache/download"],
            category: "Build Cache",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "homebrew-cache",
            displayName: "Homebrew Downloads",
            level: .developer,
            pathTemplates: ["~/Library/Caches/Homebrew"],
            category: "Package Manager",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "composer-cache",
            displayName: "Composer Cache",
            level: .developer,
            pathTemplates: ["~/.composer/cache", "~/Library/Caches/composer"],
            category: "Package Manager",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "uv-cache",
            displayName: "uv Cache",
            level: .developer,
            pathTemplates: ["~/Library/Caches/uv"],
            category: "Package Manager",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "bun-cache",
            displayName: "Bun Install Cache",
            level: .developer,
            pathTemplates: ["~/.bun/install/cache"],
            category: "Package Manager",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "deno-cache",
            displayName: "Deno Cache",
            level: .developer,
            pathTemplates: ["~/Library/Caches/deno"],
            category: "Package Manager",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            // The XDG cache directory CLI tools use on macOS (Hugging Face, Puppeteer,
            // pre-commit, gh, and friends). Cache-only by spec: tools must tolerate it
            // being cleared, the same contract as ~/Library/Caches.
            id: "xdg-cache",
            displayName: "Dev Tool Caches (~/.cache)",
            level: .developer,
            pathTemplates: ["~/.cache"],
            category: "Caches",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            // Opt-in: `mvn install` puts locally built artifacts here that no remote
            // repository can give back, unlike a pure download cache.
            id: "maven-repository",
            displayName: "Maven Local Repository",
            level: .developer,
            pathTemplates: ["~/.m2/repository"],
            category: "Package Manager",
            deletesContentsNotDirectory: true,
            requiresExplicitOptIn: true
        ),
        CleanupTarget(
            id: "jetbrains-cache",
            displayName: "JetBrains IDE Caches",
            level: .developer,
            pathTemplates: ["~/Library/Caches/JetBrains"],
            category: "IDE",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "unity-cache",
            displayName: "Unity Asset Cache",
            level: .developer,
            pathTemplates: ["~/Library/Unity/cache"],
            category: "Build Cache",
            deletesContentsNotDirectory: true,
            regenerates: true
        ),
        CleanupTarget(
            id: "docker-prune",
            displayName: "Docker System Prune",
            level: .developer,
            pathTemplates: [],
            category: "Docker",
            action: .dockerPrune,
            usesDynamicPaths: true,
            requiresExplicitOptIn: true
        ),
    ]

    // MARK: - Level 3: Deep

    public static let level3: [CleanupTarget] = [
        CleanupTarget(
            id: "downloads-installers",
            displayName: "Old Installers (.dmg / .pkg)",
            level: .deep,
            pathTemplates: ["~/Downloads"],
            category: "Downloads",
            usesDynamicPaths: true,
            requiresIndividualSelection: true
        ),
        CleanupTarget(
            id: "xcode-archives",
            displayName: "Xcode Archives",
            level: .deep,
            pathTemplates: ["~/Library/Developer/Xcode/Archives"],
            category: "Xcode",
            // Enumerate each .xcarchive bundle so the user picks specific builds:
            // archives hold dSYMs you cannot regenerate for an already-shipped build.
            usesDynamicPaths: true,
            requiresIndividualSelection: true
        ),
        CleanupTarget(
            id: "old-simulators",
            displayName: "Unused Simulators",
            level: .deep,
            pathTemplates: ["~/Library/Developer/CoreSimulator/Devices"],
            category: "Simulator",
            action: .simctlDeleteDevice,
            usesDynamicPaths: true,
            requiresIndividualSelection: true
        ),
        CleanupTarget(
            id: "diagnostic-logs",
            displayName: "Diagnostic & System Logs",
            level: .deep,
            pathTemplates: [
                "~/Library/Logs/DiagnosticReports",
                "/Library/Logs/DiagnosticReports",
                "~/Library/Logs/CrashReporter"
            ],
            category: "Logs",
            requiresIndividualSelection: true,
            respectsLogAgeThreshold: true
        ),
        CleanupTarget(
            // Models are deliberate multi-gigabyte downloads, not regenerable junk:
            // strictly opt-in, one explicit checkbox for the whole store.
            id: "ollama-models",
            displayName: "Ollama Models",
            level: .deep,
            pathTemplates: ["~/.ollama/models"],
            category: "AI Models",
            requiresExplicitOptIn: true
        ),
        CleanupTarget(
            id: "time-machine-snapshots",
            displayName: "Time Machine Local Snapshots",
            level: .deep,
            pathTemplates: [],
            category: "Snapshots",
            // Each selected snapshot is removed with `tmutil deletelocalsnapshots <date>`.
            // Backups, so manual selection only. OS-update snapshots are never offered.
            action: .tmutilDeleteSnapshot,
            usesDynamicPaths: true,
            requiresIndividualSelection: true
        ),
    ]
}
