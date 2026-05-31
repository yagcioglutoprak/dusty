// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleanerEngine",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CleanerEngine", targets: ["CleanerEngine"]),
    ],
    targets: [
        .target(name: "CleanerEngine"),
        .testTarget(name: "CleanerEngineTests", dependencies: ["CleanerEngine"]),
    ]
)
