# Repo Layout

## Structure

The skill package ships the icon catalog directly in four style roots:

- `outline/`
- `fill/`
- `micro-bold/`
- `outline-duo/`
- `glyph-duo/`

Each style root contains category folders such as:

- `ui-layout`
- `communication`
- `files`
- `users`
- `maps-location`
- `technology-devices`

## Filename format

SVG filenames follow:

```text
<size>px_<slug>.svg
```

Examples:

- `18px_accessibility.svg`
- `24px_arrow-up-right.svg`
- `32px_folder-plus.svg`

Interpretation:

- `size`: intended pixel grid
- `slug`: hyphenated icon name used for search and family matching

## Style heuristics

- `outline`: safest default for app UI, settings, navigation, forms, tables
- `fill`: stronger emphasis for badges, quick actions, utility clusters
- `micro-bold`: heavier 20px compact set for denser utility surfaces and stronger affordances
- `outline-duo`: two-tone but still airy; useful when the product already uses accent fills
- `glyph-duo`: visually heaviest; better for illustration-like or more expressive surfaces

## Search heuristics

Search usually works best from the icon concept, not the exact filename.

Good queries:

- `chevron right`
- `user add`
- `calendar event`
- `cloud upload`

If results are noisy:

1. Add a second noun or modifier.
2. Constrain style.
3. Constrain size.
4. Constrain category.

## Export guidance

Preserve original files whenever possible. Copy the chosen SVG into the consuming project and let that project decide whether to inline, bundle, or transform it.
