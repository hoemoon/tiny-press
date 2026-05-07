# tiny press — macOS app

Menu-bar companion to [`core`](../core). Register a
folder, the app watches it, rebuilds on change, serves a live preview at
`http://127.0.0.1:<port>/`, and (when Tailscale is installed) mirrors
the preview onto the user's tailnet at `https://<host>.<tailnet>.ts.net/`.

## Requirements

- macOS 26+
- Xcode 26 (Swift 6.3)
- [Tuist 4.x](https://tuist.io) — `brew install tuist`
- The `core/` sibling folder must exist (it does in this monorepo; `Project.swift` references `.local(path: "../core")`)
- Optional: `tailscale` CLI installed (Tailscale.app or `brew install tailscale`)
  — enables tailnet sharing

## Quick start

```bash
git clone https://github.com/hoemoon/tiny-press.git
cd tiny-press/mac
tuist install
tuist generate
open TinyPress.xcworkspace      # or use xcodebuild
```

The `.xcodeproj` / `.xcworkspace` are git-ignored. `Project.swift` is the
source of truth.

## Layout

```
mac/
├── Project.swift              # Tuist DSL
├── Tuist.swift
├── TinyPress/
│   ├── AppDelegate.swift
│   ├── AppState.swift
│   ├── Models/
│   │   ├── ManagedSite.swift
│   │   └── SiteStore.swift
│   ├── Services/
│   │   ├── BookmarkManager.swift
│   │   ├── BuildCoordinator.swift
│   │   ├── FolderWatcher.swift
│   │   ├── PreviewServer.swift     # Hummingbird, live-reload via SSE
│   │   └── TailscaleServeAdapter.swift
│   ├── UI/                          # Programmatic AppKit only — no .xib / .storyboard
│   ├── TinyPress.entitlements
│   └── Assets.xcassets/
├── TinyPressTests/
├── scripts/
│   └── build-dmg.sh
└── docs/
    └── RELEASE.md                   # how to ship
```

## Bundle ID & code signing

`Project.swift` defines `bundleIDPrefix = "com.tinypress"`. Change it to
your Apple Developer team's prefix before signing. App Sandbox is
intentionally disabled — see the comment in `TinyPress.entitlements`.

## Distribution

Two stages: ad-hoc unsigned `.dmg` for internal alpha, Developer ID
signed + notarized `.dmg` for wider distribution. See
[`docs/RELEASE.md`](docs/RELEASE.md).

```bash
./scripts/build-dmg.sh                  # ad-hoc unsigned
./scripts/build-dmg.sh --sign --notarize # Developer ID + notarized
```

## License

MIT.
