# tiny press

A tiny static site generator.

`TinyPressKit` Swift package + `tinypress` CLI: turns a markdown folder into
a static HTML site. Supports both the conventional `content/posts/` layout
and an Obsidian/naverp-style flat layout. UI-framework-free — can be
embedded in other clients.

## Requirements

- macOS 26+ / Xcode 26 (Swift 6.3)
- Optional: Tailscale.app for tailnet preview sharing

## Quick start

```bash
# via Homebrew
brew install hoemoon/tinypress/tinypress

# or from source
git clone https://github.com/hoemoon/tiny-press.git
cd tiny-press/core
swift run tinypress init demo
cd demo && swift run tinypress build
```

## Documentation

- [`core/MANUAL.md`](core/MANUAL.md) — CLI reference
- [`core/docs/CONTENT.md`](core/docs/CONTENT.md) — frontmatter + folder layouts
- [`core/docs/THEMING.md`](core/docs/THEMING.md) — building a custom theme

## License

MIT — see [`LICENSE`](LICENSE).
