# tiny press

A tiny static site generator with a macOS menu-bar companion.

A monorepo holding two pieces:

| Folder | Contents |
|---|---|
| [`core/`](core) | `TinyPressKit` Swift package + `tinypress` CLI. Generates a static site from a markdown folder. UI-framework-free; reused by every client. |
| [`mac/`](mac) | macOS AppKit menu-bar app. Watches a registered folder, rebuilds via `TinyPressKit`, serves a live preview, mirrors it onto Tailscale. Built with Tuist. |
| `ios/` (Phase 4) | UIKit app — not in this repo yet. |

## Requirements

- macOS 26+ / Xcode 26 (Swift 6.3)
- [Tuist 4.x](https://tuist.io) for the macOS app — `brew install tuist`
- Optional: Tailscale.app for tailnet preview sharing

## Quick start

```bash
git clone https://github.com/hoemoon/tiny-press.git
cd tiny-press

# Run the CLI from the package
cd core && swift run tinypress init demo && cd demo && swift run tinypress build

# Or generate the macOS app project and run it from Xcode
cd ../mac && tuist install && tuist generate && open TinyPress.xcworkspace
```

## Documentation

- [`core/docs/CONTENT.md`](core/docs/CONTENT.md) — frontmatter reference for content authors
- [`core/docs/THEMING.md`](core/docs/THEMING.md) — building a custom theme
- [`mac/docs/RELEASE.md`](mac/docs/RELEASE.md) — packaging the macOS app for distribution

## License

MIT — see [`LICENSE`](LICENSE).
