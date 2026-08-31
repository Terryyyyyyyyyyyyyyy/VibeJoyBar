// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "VibeJoyBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "VibeJoyBar", targets: ["VibeJoyBar"]),
    ],
    targets: [
        .executableTarget(
            name: "VibeJoyBar",
            path: "Sources/VibeJoyBar",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "VibeJoyBarTests",
            dependencies: ["VibeJoyBar"],
            path: "Tests/VibeJoyBarTests"
        ),
    ]
)
