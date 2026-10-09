// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CUITNet",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CUITNet", targets: ["CUITNet"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4"),
    ],
    targets: [
        .target(name: "CUITNetCore"),
        .executableTarget(
            name: "CUITNet",
            dependencies: ["CUITNetCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                // Sparkle.framework 打包在 Contents/Frameworks 里
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(name: "CUITNetCoreTests", dependencies: ["CUITNetCore"]),
    ],
    swiftLanguageModes: [.v6]
)
