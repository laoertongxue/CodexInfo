// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexInfo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexInfoCore", targets: ["CodexInfoCore"]),
        .library(name: "CodexInfoMCPKit", targets: ["CodexInfoMCPKit"]),
        .executable(name: "codexinfo-tests", targets: ["CodexInfoTests"])
    ],
    targets: [
        .target(name: "CodexInfoCore", path: "Sources/CodexInfoCore"),
        .target(
            name: "CodexInfoMCPKit",
            dependencies: ["CodexInfoCore"],
            path: "Sources/CodexInfoMCPKit"
        ),
        .executableTarget(
            name: "CodexInfoTests",
            dependencies: ["CodexInfoCore", "CodexInfoMCPKit"],
            path: "Sources/CodexInfoTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
