// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CUITNet",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CUITNet", targets: ["CUITNet"]),
    ],
    targets: [
        .target(name: "CUITNetCore"),
        .executableTarget(name: "CUITNet", dependencies: ["CUITNetCore"]),
        .testTarget(name: "CUITNetCoreTests", dependencies: ["CUITNetCore"]),
    ],
    swiftLanguageModes: [.v6]
)
