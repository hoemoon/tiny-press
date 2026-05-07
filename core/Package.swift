// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TinyPress",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "TinyPressKit", targets: ["TinyPressKit"]),
        .executable(name: "tinypress", targets: ["tinypress-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
        .package(url: "https://github.com/stencilproject/Stencil.git", from: "0.15.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.4.0"),
    ],
    targets: [
        .target(
            name: "TinyPressKit",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                "Yams",
                "Stencil",
            ],
            resources: [.copy("Resources/themes")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "tinypress-cli",
            dependencies: [
                "TinyPressKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TinyPressKitTests",
            dependencies: ["TinyPressKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
