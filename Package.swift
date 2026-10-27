// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexDisplaySwitch",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexDisplaySwitch", targets: ["CodexDisplaySwitch"]),
        .executable(name: "codex-displays", targets: ["codex-displays"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/waydabber/AppleSiliconDDC.git",
            revision: "67ff964ab8123d9d35fadf7d8e1a7c677d31da14"
        ),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "DisplayPower",
            dependencies: [.product(name: "AppleSiliconDDC", package: "AppleSiliconDDC")]
        ),
        .executableTarget(
            name: "CodexDisplaySwitch",
            dependencies: ["DisplayPower"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "codex-displays",
            dependencies: ["DisplayPower", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
    ]
)
