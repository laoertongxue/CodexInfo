// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexInfo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexInfoCore", targets: ["CodexInfoCore"]),
        .executable(name: "codexinfo-tests", targets: ["CodexInfoTests"])
    ],
    targets: [
        .target(name: "CodexInfoCore", path: "Sources/CodexInfoCore"),
        .executableTarget(
            name: "CodexInfoTests",
            dependencies: ["CodexInfoCore"],
            path: "Sources/CodexInfoTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
