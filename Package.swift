// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexRing",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexRingCore", targets: ["CodexRingCore"]),
        .executable(name: "codex-ring", targets: ["CodexRingApp"]),
    ],
    targets: [
        .target(
            name: "CodexRingCore",
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("JavaScriptCore")]
        ),
        .executableTarget(name: "CodexRingApp", dependencies: ["CodexRingCore"]),
        .testTarget(name: "CodexRingCoreTests", dependencies: ["CodexRingCore"]),
    ]
)
