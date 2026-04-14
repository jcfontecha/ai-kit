---
name: nucleo-icons
description: Search, shortlist, and download SVG icons from the Nucleo icon catalog hosted in a private GitHub repo. Use when Codex needs to pick icons for UI features, product concepts, navigation, status states, or marketing surfaces; compare outline, fill, micro-bold, or duo variants; or fetch exact SVG assets into another repo without cloning or manually browsing thousands of files.
---

# Nucleo Icons

Use this repo as the skill package. Prefer remote GitHub search and download through the bundled scripts so the consuming repo does not need a local clone of the icon catalog.

## Quick Start

1. Search candidates with `scripts/search_nucleo_icons.py`.
2. Narrow by `--style`, `--size`, or `--category` when the surface already implies them.
3. Download chosen SVGs with `scripts/download_nucleo_icon.py`.

```bash
python3 scripts/search_nucleo_icons.py "settings" --source remote
python3 scripts/search_nucleo_icons.py "warning triangle" --source remote --style outline --size 18 --limit 8
python3 scripts/download_nucleo_icon.py --query "warning triangle" --style outline --size 18 --out /tmp/icons
```

## Workflow

### 1. Find candidates

Start with a concept, not a guessed filename. Search script ranking favors slug matches first, then category and partial token matches.

Prefer short noun phrases:

- `user plus`
- `cloud upload`
- `calendar event`
- `arrow up right`

If the user already knows the visual direction, filter aggressively:

- `--style outline` for UI chrome, controls, and low-visual-weight surfaces
- `--style fill` for emphatic marks and dense toolbars
- `--style micro-bold` for compact, heavier 20px glyphs
- `--style outline-duo` or `--style glyph-duo` when a two-tone look is appropriate
- `--size 18` or `--size 24` when matching an existing icon grid

Use `--source remote` unless you are intentionally operating on a full local checkout of the catalog.

Use `--json` when another tool or script should consume the results.

### 2. Judge fit

Prefer exact metaphor matches over approximate keyword overlap. If several icons are close, compare the slug families first:

- `plus`, `add`, `create`
- `alert`, `warning`, `triangle-warning`
- `mail`, `send`, `paper-plane`

Read `references/repo-layout.md` when you need a concise map of the style roots, category folders, and filename conventions.

### 3. Export assets

Use the download script instead of handwritten `git`, `curl`, or `cp` commands when the icon was selected by query. It resolves the top result deterministically and downloads only the requested SVG contents.

Examples:

```bash
python3 scripts/download_nucleo_icon.py --path outline/ui-layout/18px_triangle-warning.svg --out ../app/assets/icons
python3 scripts/download_nucleo_icon.py --query "search magnifier" --style outline --size 18 --out ../app/assets/icons --flatten
python3 scripts/download_nucleo_icon.py --query "user profile" --style outline --size 18 --out ../app/assets/icons --limit 3
```

## Defaults

- Assume GitHub CLI `gh` is installed and authenticated for access to the private repo.
- Default remote catalog source is `jcfontecha/nucleo-icons-skill@main`.
- Prefer `outline` unless the caller clearly wants a heavier or two-tone treatment.
- Prefer `micro-bold` when the caller wants a compact, punchier 20px icon set.
- Prefer the smallest size that matches the target UI system; do not upscale an 18px icon into a 24px slot if a native 24px variant exists.
- Preserve original SVG contents. Do not rewrite paths, colors, or dimensions unless the user explicitly asks for icon editing.

## Resources

### `scripts/_catalog.py`

Shared catalog indexing and ranking logic used by the search and export scripts.

### `scripts/search_nucleo_icons.py`

Search and rank icons by concept, style, category, and size. Supports remote GitHub search without cloning the repo.

### `scripts/download_nucleo_icon.py`

Download exact SVG assets into a target directory from either explicit repo-relative paths or ranked search results.

### `references/repo-layout.md`

Compact reference for folder structure, naming rules, and style heuristics.
