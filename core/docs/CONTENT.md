# Content reference

This page documents the YAML frontmatter that `tinypress` understands.

## File layout

`tinypress` supports two layouts and auto-detects which one is in use:

### Structured (canonical)

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

### Flat (Obsidian-style)

```
<site_root>/                 # often no tinypress.yml or content/ subdir
├── index.md                 # optional homepage
├── 260124144615127ua.md     # every .md at the root is a post by default
├── 260124144615127ua/       # sibling asset folder, Obsidian convention
│   ├── 01.png
│   └── 02.jpg
├── 260303233251216jo.md
└── about.md                 # to make this a page, set `kind: page` in its frontmatter
```

Flat layout is auto-selected when neither `posts/` nor `pages/` exists
under the content root. It pairs naturally with archives like
`naverp` where each `.md` lives next to its image folder. Concretely:

- Every `.md` at the content root is a `post` unless its frontmatter sets
  `kind: page`.
- A sibling directory whose name matches the file's basename is treated
  as a per-page **asset sidecar**. Its contents are copied into the
  page's output directory.
- Body image links of the form `![alt](./<basename>/foo.png)` — i.e.
  pointing into the page's own asset folder — are automatically rewritten
  to `![alt](./foo.png)` so they resolve against the published URL. Other
  link paths (absolute, remote, pointing into a different folder) are
  untouched.
- `tinypress.yml` is optional. When absent, defaults apply.

The source root itself acts as the content root when there's no
`content/` subfolder, so `tinypress build --source <flat-folder>` works
directly.

> **Permalink note.** Flat-mode asset sidecars require `permalinkStyle: pretty`
> (the default). With `file` style, the sidecar copy is skipped and a build
> warning is emitted.

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
| `kind` | `post` \| `page` | inferred from layout (see [File layout](#file-layout)) | Explicit override of the page kind. In structured mode the directory normally decides; in flat mode every page defaults to `post`. |
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

Image and link paths are emitted verbatim, with one exception in flat
mode: self-reference image paths of the form `./<basename>/<file>` are
rewritten to `./<file>` so they match the location where the per-page
asset sidecar is copied. Other paths — absolute (`/images/foo.png`),
remote (`https://...`), or pointing into another page's folder — pass
through unchanged.

Place static assets under `static/` and reference them with absolute
paths (`/images/foo.png`). The `static/` convention works in both
layouts.
