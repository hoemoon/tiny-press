# tiny press

`TinyPressKit` Swift package + `tinypress` CLI: turns a markdown folder into
a static HTML site. UI-framework-free; can be embedded in other clients.

## Toolchain

Xcode 26 / Swift 6.3. If `xcode-select` points at the command-line tools,
prefix commands with:

```bash
export DEVELOPER_DIR=/Applications/Xcode-26.5.0.app/Contents/Developer
```

## Layout

- `core/` — `TinyPressKit` Swift package + `tinypress` CLI. Markdown
  folder → static HTML. Swift Testing.

## Common commands

```bash
cd core
swift build -Xswiftc -warnings-as-errors
swift test
```

## Conventions

- `TinyPressKit` is UI-framework-free. Swift 6 strict concurrency
  (`swiftLanguageMode(.v6)`).
- `@Observable` (Swift Observation), not Combine.
- `core/MANUAL.md` documents the full CLI surface. Changes to CLI flags
  must update MANUAL.md in the same commit — invoke the `/menual` skill
  (or run `python3 core/scripts/generate-manual.py` directly) to regenerate
  the fenced `BEGIN_HELP`/`END_HELP` blocks from `tinypress --help`.
- **Conventional Commits**: `feat:`, `fix:`, `chore:`, `docs:`, `test:`,
  `refactor:`. End commit body with `Co-Authored-By: Claude …` when
  Claude wrote the change.

## Releasing

The CLI is shipped through a personal Homebrew tap. The `tinypress`
formula builds from the source tarball at the matched git tag — no dmg
involved.

```bash
git tag -a v0.X.Y -m "..." && git push origin v0.X.Y
gh release create v0.X.Y --generate-notes
```

After the GitHub release exists, bump the tap at
[`hoemoon/homebrew-tinypress`](https://github.com/hoemoon/homebrew-tinypress):

```bash
TAG=v0.X.Y
SRC_SHA=$(curl -sL https://github.com/hoemoon/tiny-press/archive/refs/tags/$TAG.tar.gz | shasum -a 256 | awk '{print $1}')
echo "src=$SRC_SHA"
```

In the tap repo update `Formula/tinypress.rb` — bump `url` to the new
tag and `sha256` to `$SRC_SHA`. Validate and push:

```bash
brew style hoemoon/tinypress/tinypress
brew audit --strict --online hoemoon/tinypress/tinypress
brew uninstall tinypress
brew install --build-from-source hoemoon/tinypress/tinypress
brew test hoemoon/tinypress/tinypress
```

`brew audit --new` (notability check) is irrelevant for a personal tap;
skip it.

Note: `Formula/tinypress.rb` installs the binary into `libexec` and
exposes a shell-script wrapper at `bin/tinypress`. SPM's
`resource_bundle_accessor` resolves `Bundle.main.bundleURL` against the
launch path, so a `bin/` symlink would look for
`TinyPress_TinyPressKit.bundle` next to the symlink and abort with
*"could not load resource bundle"*. The wrapper makes
`_NSGetExecutablePath` report the libexec location.

## More docs

- `core/MANUAL.md` — CLI reference
- `core/docs/CONTENT.md` — frontmatter reference for site authors
- `core/docs/THEMING.md` — building a theme
