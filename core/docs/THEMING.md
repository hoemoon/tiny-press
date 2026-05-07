# Theming

A theme is a folder containing `theme.json`, a `layouts/` directory of
Stencil templates, and an `assets/` directory of static files.

## Folder layout

```
my-theme/
├── theme.json
├── layouts/
│   ├── base.html
│   ├── post.html
│   ├── page.html
│   └── index.html
└── assets/
    └── style.css
```

`assets/` is copied verbatim into `<output>/assets/` at build time.

## `theme.json`

```json
{
  "name": "my-theme",
  "version": "0.1.0",
  "author": "you",
  "defaultLayouts": {
    "post": "post",
    "page": "page",
    "index": "index"
  }
}
```

`defaultLayouts` maps a `Page.Kind` (`post` / `page` / `index`) to the
layout file used when a piece of content does not specify one in its
frontmatter.

## Templates

Templates use [Stencil](https://stencil.fuller.li). The renderer wires up
a `FileSystemLoader` rooted at `layouts/`, so `{% extends %}` and
`{% include %}` resolve against sibling files.

### Context

Every layout receives:

| Variable | Type | Notes |
| --- | --- | --- |
| `site` | dict | `title`, `description`, `author`, `baseURL`, `language`, `theme`. |
| `page` | dict | `title`, `kind`, `permalink`, `slug`, `tags`, `draft`, `date`, `dateISO`, `extra`. |
| `content` | string | Rendered HTML body. Available on `post` / `page`. |
| `posts` | list | Available on `index`. Pre-sorted by date desc. Each entry includes `excerpt`. |

### Inheritance

The default theme uses a single `base.html` skeleton:

```html
<!-- layouts/base.html -->
<!DOCTYPE html>
<html lang="{{ site.language }}">
  <head>
    <title>{% block title %}{{ page.title }} · {{ site.title }}{% endblock %}</title>
  </head>
  <body>
    {% block content %}{% endblock %}
  </body>
</html>
```

```html
<!-- layouts/post.html -->
{% extends "base.html" %}
{% block content %}
<article>
  <h1>{{ page.title }}</h1>
  {{ content }}
</article>
{% endblock %}
```

## Selecting a theme

In `tinypress.yml`:

```yaml
theme: default            # built-in
theme: my-theme           # also looked up in <site>/themes/my-theme/
theme: ./themes/custom    # explicit relative path
```

Path-style values are resolved against the site root.

## Per-page layout override

A frontmatter `layout: <name>` field overrides `defaultLayouts`:

```yaml
---
title: Special
layout: longform
---
```

Looks for `layouts/longform.html`.

## Built-in themes

`tinypress` ships with one theme:

- `default` — minimal, content-first, dark-mode aware.

Future themes will follow the same folder layout described above.
