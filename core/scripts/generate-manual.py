#!/usr/bin/env python3
"""Regenerate `core/MANUAL.md` help blocks from `tinypress --help`.

The manual is hand-written prose plus auto-filled synopsis blocks
delimited by `<!-- BEGIN_HELP:<name> -->` / `<!-- END_HELP:<name> -->`.
This script:

  1. Builds the `tinypress` CLI in debug mode.
  2. Captures `--help` for the root and each known subcommand.
  3. Replaces the body between every matching marker pair with a
     fenced code block containing that help output.

It is invoked by:
  - `.githooks/pre-commit` (auto-stage on local commits)
  - GitHub Actions CI (drift check — fails PR if MANUAL.md is stale)

Usage:
  python3 core/scripts/generate-manual.py            # rewrite in place
  python3 core/scripts/generate-manual.py --check    # exit 1 if stale
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

# Subcommand names to capture. Add new entries here when a new command
# (e.g. `preview`, `serve`, `share`) lands. The root entry uses the
# empty argument list. Keep this sorted to make diffs predictable.
COMMANDS: dict[str, list[str]] = {
    "root": [],
    "build": ["build"],
    "init": ["init"],
    "preview": ["preview"],
    "serve": ["serve"],
}

CORE = Path(__file__).resolve().parent.parent
MANUAL = CORE / "MANUAL.md"
BINARY = CORE / ".build/debug/tinypress"

MARKER_RE = re.compile(
    r"(<!-- BEGIN_HELP:(\w+) -->)(.*?)(<!-- END_HELP:\2 -->)",
    re.DOTALL,
)


def build() -> None:
    """Compile the CLI in debug mode, suppressing output on success."""
    result = subprocess.run(
        ["swift", "build", "-c", "debug", "--product", "tinypress"],
        cwd=CORE,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        sys.exit(f"swift build failed (exit {result.returncode})")


def capture_help(args: list[str]) -> str:
    """Run the built binary with `--help` appended and return stdout."""
    result = subprocess.run(
        [str(BINARY), *args, "--help"],
        capture_output=True,
        text=True,
    )
    # ArgumentParser exits 0 on `--help`, but be defensive: fall back
    # to stderr if stdout came back empty.
    output = result.stdout or result.stderr
    return output.rstrip()


def render_block(name: str, body: str) -> str:
    """Wrap a help payload back inside its marker pair."""
    return f"<!-- BEGIN_HELP:{name} -->\n```\n{body}\n```\n<!-- END_HELP:{name} -->"


def regenerate(text: str, blocks: dict[str, str]) -> str:
    """Replace every marker block in `text` with the captured help."""
    seen: set[str] = set()

    def substitute(match: re.Match[str]) -> str:
        name = match.group(2)
        seen.add(name)
        body = blocks.get(name)
        if body is None:
            sys.exit(
                f"MANUAL.md references unknown help block "
                f"<!-- BEGIN_HELP:{name} -->. Add it to COMMANDS in "
                f"{Path(__file__).name}."
            )
        return render_block(name, body)

    rewritten = MARKER_RE.sub(substitute, text)

    missing = set(blocks) - seen
    if missing:
        sys.stderr.write(
            "warning: COMMANDS has entries with no marker in MANUAL.md: "
            f"{sorted(missing)}\n"
        )

    return rewritten


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit 1 if MANUAL.md would change instead of writing.",
    )
    args = parser.parse_args()

    build()
    blocks = {name: capture_help(argv) for name, argv in COMMANDS.items()}

    original = MANUAL.read_text()
    rewritten = regenerate(original, blocks)

    if rewritten == original:
        print(f"{MANUAL.relative_to(CORE.parent)} already up to date")
        return 0

    if args.check:
        sys.stderr.write(
            f"{MANUAL.relative_to(CORE.parent)} is out of sync with "
            f"`tinypress --help`. Run "
            f"`python3 core/scripts/generate-manual.py` and commit the diff.\n"
        )
        return 1

    MANUAL.write_text(rewritten)
    print(f"updated {MANUAL.relative_to(CORE.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
