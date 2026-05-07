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
        //
        // Hummingbird used to be listed here directly; it is now a
        // transitive dep of `TinyPressKit` (via `Live/PreviewServer`).
        .local(path: "../core"),
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
                // App boots programmatically via main.swift — no storyboard.
                // Don't set NSMainStoryboardFile at all; on macOS 26 an empty
                // string lands the status item in a floating NSSceneStatusItem
                // detached from the system menu bar (icon never appears).
            ]),
            sources: ["TinyPress/**"],
            resources: ["TinyPress/Assets.xcassets"],
            entitlements: .file(path: "TinyPress/TinyPress.entitlements"),
            dependencies: [
                .package(product: "TinyPressKit"),
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
