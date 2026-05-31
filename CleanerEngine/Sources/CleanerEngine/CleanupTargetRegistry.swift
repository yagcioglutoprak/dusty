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
            regenerates: true
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
            requiresIndividualSelection: true
        ),
        CleanupTarget(
            id: "old-simulators",
            displayName: "Unused Simulators",
            level: .deep,
            pathTemplates: ["~/Library/Developer/CoreSimulator/Devices"],
            category: "Simulator",
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
    ]
}
