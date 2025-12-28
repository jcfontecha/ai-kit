---
name: apple-docs-navigator
description: Navigate the internal Apple Developer Docs mirror in internal_docs/references/apple-developer-docs for UIKit/SwiftUI/Apple platform symbols, types, and guides. Use when asked to look up Apple documentation, platform availability, API declarations, or to locate a specific UIKit or SwiftUI doc page within this repo.
---

# Apple Docs Navigator

## Workflow

- Start with the local mirror at `internal_docs/references/apple-developer-docs`.
- Use `index.json` to resolve exact doc slugs when the user provides a symbol name or URL fragment.
- If the user gives only keywords, search within the framework folders (`uikit/`, `swiftui/`) to find likely matches.

## How to locate a doc page

1. Check `index.json` for a slug match.
   - Use `rg` to search for the symbol or URL fragment.
   - Slugs are stored like `uikit/uiviewcontroller` or `swiftui/view`.
2. Map the slug to a markdown file under the framework folder.
   - Slug `uikit/uiviewcontroller` corresponds to `internal_docs/references/apple-developer-docs/uikit/uiviewcontroller.md`.
3. Open the markdown and extract:
   - Title
   - Role (class/struct/protocol/etc.)
   - Platform availability
   - Declaration/signature if present

## Search patterns

- Exact symbol lookup:
  - `rg -n "uiviewcontroller" internal_docs/references/apple-developer-docs/index.json`
- Keyword search when the symbol is unknown:
  - `rg -n "gesture" internal_docs/references/apple-developer-docs/uikit`
  - `rg -n "layout" internal_docs/references/apple-developer-docs/swiftui`

## Notes

- Prefer exact slug matches from `index.json` over fuzzy keyword hits.
- When multiple matches exist, list the top 3 likely candidates with their file paths and ask for confirmation.
- Keep quotes short; summarize sections instead of pasting large blocks.
