# tinypress — CLI manual

`tinypress` is the command-line entry point for tiny press. The macOS
menu-bar app is a GUI wrapper over this CLI; every feature you see in
the app maps to a subcommand documented below. New behaviour lands here
first.

> Status: as of v0.1.0 the CLI ships `init` and `build`. `preview`,
> `serve`, and `share` are planned (see `../CLAUDE.md` →
> *Architecture principle*).

## Install

### Homebrew (recommended)

```bash
brew install hoemoon/tinypress/tinypress
```

### From source

```bash
git clone https://github.com/hoemoon/tiny-press.git
cd tiny-press/core
swift build -c release
cp .build/release/tinypress /usr/local/bin/
```

Requires Xcode 26 / Swift 6.3 toolchain.

## Quick start

```bash
tinypress init my-blog --title "My Blog"
cd my-blog
tinypress build
python3 -m http.server -d _site 8000   # preview locally
```

## Commands

The blocks marked `<!-- BEGIN_HELP:* -->` are regenerated from
`tinypress --help` by `core/scripts/generate-manual.py`. Don't edit
them by hand — see *Keeping the manual in sync* below.

<!-- BEGIN_HELP:root -->
```
OVERVIEW: tiny press — a tiny static site generator.

USAGE: tinypress <subcommand>

OPTIONS:
  --version               Show the version.
  -h, --help              Show help information.

SUBCOMMANDS:
  init                    Scaffold a new tiny press site at the given path.
  build                   Render the site at --source into the --output folder.

  See 'tinypress help <subcommand>' for detailed help.
```
<!-- END_HELP:root -->

### `tinypress init <path>`

Scaffold a new tiny press site at `<path>`. Creates the folder if
absent; refuses to overwrite a non-empty directory.

<!-- BEGIN_HELP:init -->
```
OVERVIEW: Scaffold a new tiny press site at the given path.

USAGE: tinypress init <path> [--title <title>]

ARGUMENTS:
  <path>                  Folder where the new site will be created.

OPTIONS:
  --title <title>         Title for the new site. (default: My Site)
  --version               Show the version.
  -h, --help              Show help information.
```
<!-- END_HELP:init -->

| Option | Default | Description |
|---|---|---|
| `<path>` | *(required)* | Folder to create. |
| `--title <title>` | `My Site` | Title written into `tinypress.yml`. |

Creates:

```
<path>/
├── tinypress.yml                 # SiteConfig (title/theme/language/...)
├── content/
│   ├── posts/hello.md            # sample post with frontmatter
│   └── pages/about.md            # sample page
└── static/                       # static assets, copied as-is
```

Prints the absolute path of the new site to stdout. Logs go to stderr.

**Example**

```bash
$ tinypress init ./demo --title "Demo Site"
Created site at /Users/me/demo
Next: cd ./demo && tinypress build
/Users/me/demo
```

### `tinypress build`

Render the site at `--source` into `--output`. Idempotent: same input
produces same output tree.

<!-- BEGIN_HELP:build -->
```
OVERVIEW: Render the site at --source into the --output folder.

USAGE: tinypress build [--source <source>] [--output <output>] [--include-drafts]

OPTIONS:
  -s, --source <source>   Source folder. Defaults to the current directory.
                          (default: .)
  -o, --output <output>   Output folder. Defaults to <source>/_site.
  --include-drafts        Include posts marked draft: true.
  --version               Show the version.
  -h, --help              Show help information.
```
<!-- END_HELP:build -->

| Option | Default | Description |
|---|---|---|
| `-s`, `--source <path>` | `.` | Source folder containing `tinypress.yml`. |
| `-o`, `--output <path>` | `<source>/_site` | Output folder. Wiped on each build (dot-prefixed entries preserved). |
| `--include-drafts` | off | Include posts with `draft: true` in frontmatter. |

Behaviour:

- The output folder is cleared at the start of each build, except for
  dot-prefixed entries (`.git`, `.DS_Store`, ...).
- Pages with `draft: true` are excluded by default; `--include-drafts`
  flips this for the run.
- Per-page errors (bad YAML, missing layout) fail just that page and
  surface in the build report's warnings; the rest of the build
  continues.
- Duplicate slugs are a hard build error.

Prints the absolute output path to stdout when the build succeeds.
Returns exit code `1` on failure (build report messages on stderr).

**Example**

```bash
$ tinypress build --source ./demo --include-drafts
Building /Users/me/demo → /Users/me/demo/_site
Built 4 page(s) and copied 3 asset(s) in 0.123s
/Users/me/demo/_site
```

## Folder convention

```
my-site/
├── tinypress.yml                 # SiteConfig
├── content/
│   ├── posts/                    # Page.Kind.post — slug derived from filename
│   │   └── 2026-01-01-hello.md
│   ├── pages/                    # Page.Kind.page
│   │   └── about.md
│   └── index.md                  # Page.Kind.index (optional)
└── static/                       # copied verbatim into output root
    └── images/
```

Authoring details (frontmatter fields, theme overrides) live in
[`docs/CONTENT.md`](docs/CONTENT.md) and [`docs/THEMING.md`](docs/THEMING.md).

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success. |
| 1 | Build or scaffold failed (message on stderr). |
| 2 | Argument parsing error (ArgumentParser default). |
| 64 | `--help` / `--version` exits (ArgumentParser convention). |

## Logging

All status and error messages go to **stderr** with no prefix for info
and an `error: ` prefix for errors. The single line on **stdout** is
the result path, so `tinypress` is safe to compose in shell pipelines:

```bash
output=$(tinypress build --source ./demo)
rsync -av "$output/" user@host:/var/www/demo/
```

## Mac app ↔ CLI mapping

The menu-bar app exposes the same operations through a GUI. Every
action below has a CLI equivalent (or will, per the parity plan in
`CLAUDE.md`):

| App action | CLI equivalent |
|---|---|
| Add Site → choose folder | *(stateless)* — pass the folder to `build` / `preview` directly |
| Build | `tinypress build --source <folder>` |
| Preview (live reload) | `tinypress preview --source <folder>` *(planned)* |
| Share via Tailscale | `tinypress preview --source <folder> --share` *(planned)* |
| Settings → edit `tinypress.yml` | edit the file directly |

If you find an app feature that has no CLI equivalent, that is a bug
in the architecture — file an issue.

## Keeping the manual in sync

The fenced blocks marked `<!-- BEGIN_HELP:* -->` are filled by
`core/scripts/generate-manual.py`, which captures `tinypress --help`
output for each subcommand and rewrites the markers in place.

Two safety nets enforce that the manual stays in sync with the CLI:

- **Pre-commit hook** (`.githooks/pre-commit`) — when a commit touches
  `core/Sources/tinypress-cli/**`, the hook regenerates MANUAL.md and
  re-stages it automatically. Activate the hook once per clone:

  ```bash
  git config core.hooksPath .githooks
  ```

- **CI drift check** — the `core` job in `.github/workflows/ci.yml`
  runs `python3 core/scripts/generate-manual.py --check` and fails
  the build if the committed MANUAL.md disagrees with the captured
  help output. Even if a contributor bypasses the local hook, the
  manual cannot fall behind on `main`.

To add a new subcommand to the auto-fill set, add its name to the
`COMMANDS` map at the top of `generate-manual.py` and insert
`<!-- BEGIN_HELP:<name> -->` / `<!-- END_HELP:<name> -->` markers
in this file.
