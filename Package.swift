// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ELMUsageTracker",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ELMUsageTracker", targets: ["ELMUsageTracker"])
    ],
    targets: [
        .target(
            name: "ELMUsageCore",
            path: "Sources/ELMUsageCore"
        ),
        .executableTarget(
            name: "ELMUsageTracker",
            dependencies: ["ELMUsageCore"],
            path: "Sources/ELMUsageTracker"
        ),
        .testTarget(
            name: "ELMUsageCoreTests",
            dependencies: ["ELMUsageCore"],
            path: "Tests/ELMUsageCoreTests"
        )
    ]
)
