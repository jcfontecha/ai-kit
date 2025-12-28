---
name: gt-worktrees
description: Help configure gt.json to define post-create steps for git worktrees
---

# gt Worktree Configuration

`gt` can run repository-specific commands after a worktree is created. Configure them in `gt.json`.

## Example

```json
{
  "version": 1,
  "postCreate": [
    "cp .env.example .env.local",
    "npm install",
    "npm run build"
  ]
}
```

## Notes

- `postCreate` runs from the new worktree root.
- Use shell commands exactly as you'd run them in the repo.
- `GT_WORKTREE` is available in `postCreate` commands and points to the new worktree path.