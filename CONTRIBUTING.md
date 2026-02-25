# Contributing to AIKit

Thanks for contributing.

## Support model

AIKit is currently maintained on a best-effort basis. Issues and pull requests are welcome, but response times are not guaranteed.

## Prerequisites

- Xcode with Swift 6.2 toolchain
- macOS environment for local build/test

## Local setup

```bash
git clone https://github.com/jcfontecha/ai-kit.git
cd ai-kit
swift build
swift test
```

If you need to build UI-dependent demo targets, use:

```bash
xcb demo-swiftui
```

## Development expectations

- Keep changes focused and minimal.
- Prefer type-safe APIs and explicit state modeling.
- Add or update tests for non-trivial behavior changes.
- Preserve existing module boundaries (`AIKit`, providers, elements, macros).

## Commit and PR standards

- Use Conventional Commit style for commit messages:
  - `feat: ...`
  - `fix: ...`
  - `docs: ...`
  - `chore: ...`
  - `test: ...`
- Keep PRs reviewable (one cohesive concern per PR).
- Include a short validation section in the PR description listing commands run.

## Before opening a PR

Run:

```bash
swift build
swift test
```

If your change affects docs/examples, include a brief note of what was validated.

## Pull request checklist

- [ ] Scope is focused and intentional
- [ ] Tests added/updated where appropriate
- [ ] `swift build` passes
- [ ] `swift test` passes
- [ ] Docs/comments updated for user-facing behavior changes

