# Content reference

This page documents the YAML frontmatter that `tinypress` understands.

## File layout

```
content/
├── index.md              # optional homepage
├── posts/
│   └── 2026-01-01-hello.md
└── pages/
    └── about.md
```

- Anything under `content/posts/` becomes a `post` (listed on the index).
- Anything under `content/pages/` becomes a `page` (not listed).
- A top-level `content/index.md` becomes the homepage; the rendered post
  list is still injected into the page context, so you can mix prose and
  the archive on the homepage.

## Frontmatter

All fields are optional. The block is wrapped in `---`:

```yaml
---
title: Hello, world
date: 2026-01-15
tags: [intro, meta]
slug: hello
draft: false
layout: post
extra:
  hero: /images/hero.jpg
  reading_time: 4
---

Body markdown goes here.
```

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `title` | string | derived from slug | Used in `<title>` and post lists. |
| `date` | ISO date | — | Sorts posts on the index. |
| `tags` | string list | `[]` | Rendered as a tag pill row in the default theme. |
| `slug` | string | filename | Overrides the URL slug. |
| `draft` | bool | `false` | Excluded from build unless `--include-drafts`. |
| `layout` | string | inferred from kind | Layout file name (without `.html`). |
| `extra` | map | `{}` | Free-form values — strings, ints, doubles, bools, arrays, dicts. |

`extra.*` is exposed to templates as `page.extra.<key>`.

## Slugs

If `slug` is not set, the filename is used. A leading `YYYY-MM-DD-` prefix
is stripped automatically: `2026-01-01-hello.md` → slug `hello`.

## Permalinks

Configured via `permalinkStyle` in `tinypress.yml`:

| style | post | page |
| --- | --- | --- |
| `pretty` (default) | `/posts/<slug>/` | `/<slug>/` |
| `file` | `/posts/<slug>.html` | `/<slug>.html` |

## Drafts

Set `draft: true` to exclude a post from the default build. Pass
`--include-drafts` to render them anyway — useful for previews.

## Markdown

`tinypress` accepts standard CommonMark plus the `[strikethrough]` and
table extensions provided by `swift-markdown`. Code fences with a language
hint emit `<pre><code class="language-<name>">…</code></pre>`, ready for
client-side syntax highlighting.

Image and link paths are emitted verbatim. Place static assets under
`static/` and reference them with absolute paths (`/images/foo.png`).
