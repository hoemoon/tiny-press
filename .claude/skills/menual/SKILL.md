---
name: menual
description: Regenerate `core/MANUAL.md` from the live `tinypress --help` output. Invoke after editing files under `core/Sources/tinypress-cli/`, or when the user asks to refresh, sync, or rebuild the CLI manual. Skip when only `core/Sources/TinyPressKit/` changed — kit edits don't affect the CLI surface.
---

# menual — sync MANUAL.md to the live CLI

The CLI manual at `core/MANUAL.md` is half hand-written prose, half
auto-filled `<!-- BEGIN_HELP:* -->` blocks. This skill regenerates the
auto-filled blocks so they match what `tinypress --help` actually
prints today.

## When to invoke

Run after any change that could shift the CLI surface:

- editing a `.swift` file under `core/Sources/tinypress-cli/`
- adding or removing a subcommand (also update `COMMANDS` in
  `core/scripts/generate-manual.py` and add a marker pair in
  `core/MANUAL.md`)
- the user explicitly asks to "refresh the manual", "sync the
  manual", "regenerate MANUAL.md", or similar

Don't run after pure `TinyPressKit` edits — the script still works
but it's a wasted ~1s `swift build` for no diff.

## How

From the repo root:

```bash
python3 core/scripts/generate-manual.py
```

The script:

1. Builds the `tinypress` binary in debug mode (incremental — fast
   after the first run).
2. Captures `tinypress --help` for the root and each subcommand
   listed in its `COMMANDS` map.
3. Rewrites the body of every matching `<!-- BEGIN_HELP:<name> -->` /
   `<!-- END_HELP:<name> -->` pair in `core/MANUAL.md`.

Output:

- `core/MANUAL.md already up to date` — nothing to do.
- `updated core/MANUAL.md` — file was rewritten; stage it alongside
  the CLI change in the same commit.

Use `--check` for read-only verification (exit 1 on drift) — that's
the mode the CI job runs.

## After running

If the script updated MANUAL.md, run `git diff core/MANUAL.md` to
review the synopsis change, then `git add core/MANUAL.md` so the
manual ships with the commit that changed the CLI.

If the script fails:

- *swift build failed* — usually `xcode-select` points at
  CommandLineTools instead of Xcode 26+. Re-run with
  `DEVELOPER_DIR=/Applications/Xcode-26.4.1.app/Contents/Developer`
  set.
- *MANUAL.md references unknown help block* — the manual has a
  `BEGIN_HELP:<name>` marker for a subcommand not listed in
  `COMMANDS`. Add the entry to the map or remove the marker.
