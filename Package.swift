// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexInfo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexInfoCore", targets: ["CodexInfoCore"]),
        .library(name: "CodexInfoMCPKit", targets: ["CodexInfoMCPKit"]),
        .library(name: "CodexInfoLive", targets: ["CodexInfoLive"]),
        .executable(name: "codexinfo-mcp", targets: ["CodexInfoMCP"]),
        .executable(name: "codexinfo-tests", targets: ["CodexInfoTests"])
    ],
    targets: [
        .target(name: "CodexInfoCore", path: "Sources/CodexInfoCore"),
        .target(
            name: "CodexInfoMCPKit",
            dependencies: ["CodexInfoCore"],
            path: "Sources/CodexInfoMCPKit"
        ),
        .target(
            name: "CodexInfoLive",
            dependencies: ["CodexInfoCore", "CodexInfoMCPKit"],
            path: "Sources/CodexInfoLive"
        ),
        .executableTarget(
            name: "CodexInfoMCP",
            dependencies: ["CodexInfoCore", "CodexInfoLive", "CodexInfoMCPKit"],
            path: "Sources/CodexInfoMCP"
        ),
        .executableTarget(
            name: "CodexInfoTests",
            dependencies: ["CodexInfoCore", "CodexInfoMCPKit", "CodexInfoLive"],
            path: "Sources/CodexInfoTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
