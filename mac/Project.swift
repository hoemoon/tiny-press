import ProjectDescription

// Bundle id prefix is the only thing you typically need to change before
// signing — set it to whatever Apple Developer team prefix you use.
let bundleIDPrefix = "com.tinypress"

let project = Project(
    name: "TinyPress",
    organizationName: "tiny press",
    packages: [
        // Local path keeps the macOS app and the core in lockstep during
        // development. Swap to `.remote(url:)` once `core` is
        // published on GitHub.
        .local(path: "../core"),
        .remote(
            url: "https://github.com/hummingbird-project/hummingbird",
            requirement: .upToNextMajor(from: "2.22.0")
        ),
    ],
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "MACOSX_DEPLOYMENT_TARGET": "26.0",
            "CODE_SIGN_STYLE": "Automatic",
            "ENABLE_HARDENED_RUNTIME": "YES",
            // Disable signing in CI / unattended builds. Override locally
            // with `tuist generate --` when signing is required.
            "CODE_SIGNING_REQUIRED": "NO",
            "CODE_SIGN_IDENTITY": "",
        ]
    ),
    targets: [
        .target(
            name: "TinyPress",
            destinations: .macOS,
            product: .app,
            bundleId: "\(bundleIDPrefix).app",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "LSUIElement": true,
                "LSApplicationCategoryType": "public.app-category.productivity",
                "CFBundleDisplayName": "tiny press",
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "NSHumanReadableCopyright": "© 2026 tiny press",
                // App boots programmatically; no Main.storyboard exists.
                "NSMainStoryboardFile": "",
            ]),
            sources: ["TinyPress/**"],
            resources: ["TinyPress/Assets.xcassets"],
            entitlements: .file(path: "TinyPress/TinyPress.entitlements"),
            dependencies: [
                .package(product: "TinyPressKit"),
                .package(product: "Hummingbird"),
            ]
        ),
        .target(
            name: "TinyPressTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "\(bundleIDPrefix).tests",
            deploymentTargets: .macOS("26.0"),
            sources: ["TinyPressTests/**"],
            dependencies: [.target(name: "TinyPress")]
        ),
    ]
)
