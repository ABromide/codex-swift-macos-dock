// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexDockNotifier",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CodexDockNotifierCore",
            targets: ["CodexDockNotifierCore"]
        ),
        .executable(
            name: "CodexDockNotifier",
            targets: ["CodexDockNotifier"]
        ),
        .executable(
            name: "CodexDockNotifierSmokeTest",
            targets: ["CodexDockNotifierSmokeTest"]
        )
    ],
    targets: [
        .target(
            name: "CodexDockNotifierCore"
        ),
        .executableTarget(
            name: "CodexDockNotifier",
            dependencies: ["CodexDockNotifierCore"]
        ),
        .executableTarget(
            name: "CodexDockNotifierSmokeTest",
            dependencies: ["CodexDockNotifierCore"]
        )
    ]
)
