// swift-tools-version: 6.0
import PackageDescription

// Tools 6.0 compiles the package in Swift 6 language mode: strict concurrency
// checking is on for the whole engine, and any data-race issue is a build error.
let package = Package(
    name: "CleanerEngine",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CleanerEngine", targets: ["CleanerEngine"]),
        .executable(name: "dusty", targets: ["DustyCLI"]),
    ],
    targets: [
        .target(name: "CleanerEngine"),
        .executableTarget(name: "DustyCLI", dependencies: ["CleanerEngine"]),
        .testTarget(name: "CleanerEngineTests", dependencies: ["CleanerEngine"]),
    ]
)
