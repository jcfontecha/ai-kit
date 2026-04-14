---
name: ios-swift-development
description: >
  Develop native iOS apps with Swift for this repo's architecture. Covers
  SwiftUI, protocol-backed services, Swift concurrency, Observation, and
  SwiftData persistence.
---

# iOS Swift Development

## Overview

Build native iOS features for Kauch using SwiftUI, SwiftData, Observation, and
Swift concurrency while preserving the repo's existing architectural rules.

## Repo Overrides

For this repo specifically:

- Assume iOS 26+ only. Do not add availability checks or older-iOS fallback paths.
- Prefer SwiftData over Core Data.
- Prefer Observation-based state (`@Observable`) over `ObservableObject` unless interop requires otherwise.
- Follow the repo's default architecture: `@Query` for reads, protocol-backed services for writes.
- Do not introduce MVVM by default. Add a view model only when the view has non-trivial logic beyond CRUD.
- Use the shared theme system rather than local ad hoc styling.
- Keep code organized by feature folders with small, focused files.
- Keep production Swift under `Kauch/App`, `Kauch/Core`, `Kauch/Features`, or `Kauch/Shared`.
- Add `#Preview` for every production SwiftUI view file ending in `View.swift`.
- Add unit tests around non-trivial logic using Swift Testing.

## When to Use

- Adding or changing SwiftUI features in Kauch
- Writing protocol-backed services and models
- Integrating async workflows with Swift concurrency
- Working with SwiftData models, queries, and persistence
- Adding tests and previews around non-trivial feature work

## Implementation Defaults

- Start by identifying the smallest feature folder that owns the change.
- Keep reads in views with `@Query` when possible.
- Put mutations behind a focused protocol-backed service.
- Use `@Observable` only when the view needs real orchestration or derived state.
- Prefer one primary type per file.
- Keep previews deterministic with in-memory SwiftData and explicit environment injection.

## Reference Guides

Detailed implementations in the `references/` directory:

| Guide | Contents |
|---|---|
| [Network Service with URLSession](references/network-service-with-urlsession.md) | Network Service with URLSession |
| [SwiftUI Views](references/swiftui-views.md) | SwiftUI Views |

## Best Practices

### ✅ DO

- Use SwiftUI for modern UI development
- Preserve the repo's `@Query` + service boundary
- Use async/await patterns
- Store sensitive data in Keychain
- Handle errors gracefully
- Use Observation-based state and dependency injection
- Validate external responses properly
- Implement SwiftData for persistence
- Test on iOS 26 runtime targets used by the project
- Follow the theme system and source layout guardrails
- Add Swift Testing coverage for non-trivial logic
- Add or update previews when touching UI

### ❌ DON'T

- Store tokens in UserDefaults
- Make network calls on main thread
- Introduce MVVM by default
- Invent ad hoc API layers, scaffolds, or environment-driven config
- Ignore memory leaks
- Skip error handling
- Use force unwrapping (!)
- Store passwords in code
- Ignore accessibility
- Deploy untested code
- Bypass shared theme tokens with local styling hacks
