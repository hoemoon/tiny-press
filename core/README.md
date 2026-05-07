# tiny press

> A tiny static site generator written in Swift.

`tiny press` turns a folder of Markdown files into a clean static site. It
ships as a Swift Package — `TinyPressKit` (library) + `tinypress` (CLI) —
and shares the same core with sibling apps for macOS / iOS.

- **Library**: `TinyPressKit` — UI-framework-free, embeddable in AppKit /
  UIKit / server contexts.
- **CLI**: `tinypress` — `init` and `build` subcommands.
- **Themes**: a built-in `default` theme; bring your own folder of Stencil
  layouts.
- **Drafts**: `draft: true` posts are skipped unless `--include-drafts` is
  passed.

## Requirements

- macOS 26+ or iOS 26+ (library)
- Swift 6.3+ (Xcode 26)

## Install

This package lives inside the [`tiny-press`](https://github.com/hoemoon/tiny-press)
monorepo (`Package.swift` is at `core/Package.swift`, not the repo root,
so external SPM consumption isn't supported as-is). The macOS / iOS apps
in sibling folders consume it via `.local(path: "../core")`.

To build the CLI from source:

```bash
git clone https://github.com/hoemoon/tiny-press.git
cd tiny-press/core
swift build -c release
.build/release/tinypress --help
```

## Quick start

```bash
swift run tinypress init my-site --title "My Blog"
cd my-site
swift run tinypress build
python3 -m http.server --directory _site
```

Open `http://localhost:8000` to view the site.

## Folder convention

```
my-site/
├── tinypress.yml          # SiteConfig
├── content/
│   ├── posts/             # → /posts/<slug>/
│   │   └── 2026-01-01-hello.md
│   ├── pages/             # → /<slug>/
│   │   └── about.md
│   └── index.md           # optional homepage content
└── static/                # copied verbatim into the output root
    └── images/
```

`tinypress.yml`:

```yaml
title: My Blog
description: A short tagline.
author: Your Name
theme: default
language: en
permalinkStyle: pretty   # pretty | file
```

## CLI

```bash
tinypress init <path> [--title "My Site"]
tinypress build [--source <path>] [--output <path>] [--include-drafts]
```

`stdout` carries the result path; `stderr` carries log messages so the CLI
composes well with shell pipelines.

## Embedding

```swift
import TinyPressKit

let report = try await SiteBuilder().build(
    sourceRoot: URL(fileURLWithPath: "/path/to/site"),
    outputRoot: URL(fileURLWithPath: "/path/to/out")
)
print(report.pagesGenerated, report.duration)
```

## Documentation

- [`docs/CONTENT.md`](docs/CONTENT.md) — frontmatter reference for content
  authors.
- [`docs/THEMING.md`](docs/THEMING.md) — building a custom theme.

## License

MIT — see [`LICENSE`](../LICENSE).
