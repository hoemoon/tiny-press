# tiny press

Monorepo for a tiny static site generator (`core/`) and its macOS menu-bar
companion (`mac/`). iOS app folder will be added later.

## Toolchain

Xcode 26 / Swift 6.3 / Tuist 4.x. If `xcode-select` points at the
command-line tools, prefix commands with:

```bash
export DEVELOPER_DIR=/Applications/Xcode-26.4.1.app/Contents/Developer
```

## Layout

- `core/` — `TinyPressKit` Swift package + `tinypress` CLI. Markdown
  folder → static HTML. Swift Testing.
- `mac/` — AppKit menu-bar app. Tuist generates the Xcode project from
  `Project.swift`; `.xcodeproj` and `.xcworkspace` are git-ignored.

## Common commands

```bash
# core
cd core
swift build -Xswiftc -warnings-as-errors
swift test

# mac
cd mac
tuist install && tuist generate --no-open
xcodebuild test -workspace TinyPress.xcworkspace \
    -scheme TinyPress -destination 'platform=macOS'
```

## Architecture principle: CLI is the source of truth

The macOS menu-bar app is a GUI wrapper over `tinypress`. Every
user-visible feature in the app must correspond to a `tinypress`
subcommand with equivalent behaviour, and new features ship to the CLI
first.

Concretely:

- Functionality lives in `core/` (`TinyPressKit` + `tinypress-cli`),
  not in `mac/TinyPress/Services/`. Code under `mac/` should be UI
  plumbing only — wiring AppKit views to kit/CLI behaviour.
- The mac app links `TinyPressKit` directly (in-process) rather than
  spawning the CLI binary, for low-latency UI feedback. Spawning is
  fine for one-shot operations; long-running flows (watch, preview
  server, Tailscale share) share the kit.
- If a code path has no CLI equivalent, it does not belong in `mac/`
  either — lift it to the kit and expose a `tinypress` subcommand.
- `core/MANUAL.md` documents the full CLI surface and is the contract
  the mac app honours. Changes to CLI flags must update MANUAL.md in
  the same commit.

## Conventions

- **No SwiftUI / storyboard / xib.** macOS uses AppKit programmatically.
  Future iOS will use UIKit. `TinyPressKit` is UI-framework-free.
- **`@Observable`** (Swift Observation), not Combine. AppKit views
  subscribe via `withObservationTracking { … } onChange:`.
- **Swift 6 strict concurrency** is on. `swiftLanguageMode(.v6)` for the
  package; `SWIFT_STRICT_CONCURRENCY=complete` for the app.
- **App Sandbox is intentionally OFF** for the macOS app — it shells out
  to the `tailscale` CLI for live preview sharing. See the comment in
  `mac/TinyPress/TinyPress.entitlements`.
- **Conventional Commits**: `feat:`, `fix:`, `chore:`, `docs:`, `test:`,
  `refactor:`. End commit body with `Co-Authored-By: Claude …` when
  Claude wrote the change.

## Releasing

One tag covers the whole monorepo. The macOS app produces a `.dmg`; the
core just gets a pinned commit at the tag.

### Stage 0 — unsigned dmg (testers right-click → Open the first time)

```bash
git tag -a v0.X.Y -m "..." && git push origin v0.X.Y
cd mac && ./scripts/build-dmg.sh && cd ..
gh release create v0.X.Y mac/dist/*.dmg --generate-notes
```

The `release.yml` workflow also runs but skips gracefully when the
GitHub-hosted runner lacks Xcode 26+. Local build is the source of truth
until `macos-26` runners are GA.

### Stage 1 — signed + notarized (testers double-click, just opens)

Prerequisite (once): Apple Developer enrolled, *Developer ID
Application* cert in keychain, notary credential stored as
`tinypress-notary` keychain profile. See `mac/docs/RELEASE.md`.

```bash
git tag -a v0.X.Y -m "..." && git push origin v0.X.Y
cd mac && ./scripts/build-dmg.sh --sign --notarize && cd ..
# new release:
gh release create v0.X.Y mac/dist/*.dmg --generate-notes
# replace existing release asset:
gh release upload v0.X.Y mac/dist/*.dmg --clobber
```

The script auto-derives the team id from the keychain. Override with
`TINYPRESS_TEAM_ID=...` if you have multiple Developer ID identities.

### Verify before announcing

```bash
spctl -a -vvv -t install mac/dist/TinyPress-*.dmg   # → accepted / Notarized Developer ID
xcrun stapler validate    mac/dist/TinyPress-*.dmg   # → "validate action worked"
```

### Update the Homebrew tap

After the GitHub release exists, bump the tap at
[`hoemoon/homebrew-tinypress`](https://github.com/hoemoon/homebrew-tinypress).
Both files need updating in lockstep.

```bash
TAG=v0.X.Y
SRC_SHA=$(curl -sL https://github.com/hoemoon/tiny-press/archive/refs/tags/$TAG.tar.gz | shasum -a 256 | awk '{print $1}')
DMG_SHA=$(shasum -a 256 mac/dist/TinyPress-*.dmg | awk '{print $1}')
echo "src=$SRC_SHA"
echo "dmg=$DMG_SHA"
```

In the tap repo:

- `Formula/tinypress.rb` — bump `url` to the new tag and `sha256` to `$SRC_SHA`.
- `Casks/tiny-press.rb` — bump `version` and `sha256` to `$DMG_SHA`.

Validate, commit, push:

```bash
brew style hoemoon/tinypress/tinypress
brew style --cask hoemoon/tinypress/tiny-press
brew audit --strict --online hoemoon/tinypress/tinypress
brew audit --strict --online --cask hoemoon/tinypress/tiny-press
# end-to-end:
brew uninstall --cask tiny-press; brew uninstall tinypress
brew install --build-from-source hoemoon/tinypress/tinypress
brew install --cask hoemoon/tinypress/tiny-press
brew test hoemoon/tinypress/tinypress
```

`brew audit --new` (notability check) is irrelevant for a personal tap;
skip it. Once the user-visible launch alert is dismissed once,
`open /Applications/TinyPress.app` should land an icon in the menu bar.

Notes baked in by past releases (don't undo without reading these):

- `Formula/tinypress.rb` installs the binary into `libexec` and exposes a
  shell-script wrapper at `bin/tinypress`. SPM's
  `resource_bundle_accessor` resolves `Bundle.main.bundleURL` against the
  launch path, so a `bin/` symlink would look for
  `TinyPress_TinyPressKit.bundle` next to the symlink and abort with
  *“could not load resource bundle”*. The wrapper makes
  `_NSGetExecutablePath` report the libexec location.
- The Cask depends on the dmg being **Developer ID signed +
  notarized**. Stage 0 (ad-hoc) installs but trips Gatekeeper on every
  launch.

## More docs

- `core/docs/CONTENT.md` — frontmatter reference for site authors
- `core/docs/THEMING.md` — building a theme
- `mac/docs/RELEASE.md` — Stage 1 setup steps in detail
