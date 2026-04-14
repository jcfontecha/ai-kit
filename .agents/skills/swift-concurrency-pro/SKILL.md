---
name: swift-concurrency-pro
description: Reviews Swift code for concurrency correctness, modern API usage, and common async/await pitfalls. Use when reading, writing, or reviewing Swift concurrency code, especially when fixing actor isolation, Sendable, strict concurrency, or Swift 6.2 migration issues.
license: MIT
metadata:
  author: Paul Hudson
  version: "1.0"
---

Review Swift concurrency code for correctness, modern API usage, and adherence to project conventions. Report only genuine problems - do not nitpick or invent issues.

## Fast Path

Before proposing or implementing a fix:

1. Capture the exact diagnostic and offending symbol.
2. Determine the isolation boundary: `@MainActor`, custom actor, actor instance isolation, or `nonisolated`.
3. Confirm whether the code is UI-bound or intended to run off the main actor.
4. Check project concurrency settings before giving migration-sensitive advice.

For this repo:

- Target Swift 6.2 or later.
- Assume iOS 26+ only.
- Prefer SwiftData over Core Data when persistence is involved.
- Respect the repo's architecture rather than widening the refactor scope.

Relevant build settings:

| Setting | Xcode |
|---|---|
| Swift language mode | Swift Language Version |
| Strict concurrency | `SWIFT_STRICT_CONCURRENCY` |
| Default actor isolation | `SWIFT_DEFAULT_ACTOR_ISOLATION` |
| Upcoming features | `SWIFT_UPCOMING_FEATURE_*` |

Guardrails:

- Do not recommend `@MainActor` as a blanket fix. Justify why the code is truly UI-bound.
- Prefer the smallest safe change. Do not refactor unrelated architecture during migration.
- Prefer structured concurrency over unstructured tasks. Use `Task.detached` only with a clear reason.
- Do not suggest `@unchecked Sendable` unless the type is already internally synchronized and the invariant can be stated explicitly.

Review process:

1. Scan for known-dangerous patterns using `references/hotspots.md` to prioritize what to inspect.
1. Check for recent Swift 6.2 concurrency behavior using `references/new-features.md`.
1. Validate actor usage for reentrancy and isolation correctness using `references/actors.md`.
1. Ensure structured concurrency is preferred over unstructured where appropriate using `references/structured.md`.
1. Check unstructured task usage for correctness using `references/unstructured.md`.
1. Verify cancellation is handled correctly using `references/cancellation.md`.
1. Validate async stream and continuation usage using `references/async-streams.md`.
1. Check bridging code between sync and async worlds using `references/bridging.md`.
1. Review any legacy concurrency migrations using `references/interop.md`.
1. Cross-check against common failure modes using `references/bug-patterns.md`.
1. If the project has strict-concurrency errors, map diagnostics to fixes using `references/diagnostics.md`.
1. If reviewing tests, check async test patterns using `references/testing.md`.

If doing a partial review, load only the relevant reference files.


## Core Instructions

- Target Swift 6.2 or later with strict concurrency checking.
- Compare concurrency build settings before assuming behavior should match across targets.
- Prefer structured concurrency (task groups) over unstructured (`Task {}`).
- Prefer Swift concurrency over Grand Central Dispatch for new code. GCD is still acceptable in low-level code, framework interop, or performance-critical synchronous work where queues and locks are the right tool – don't flag these as errors.
- If an API offers both `async`/`await` and closure-based variants, always prefer `async`/`await`.
- Do not introduce third-party concurrency frameworks without asking first.
- Do not suggest `@unchecked Sendable` to fix compiler errors. It silences the diagnostic without fixing the underlying race. Prefer actors, value types, or `sending` parameters instead. The only legitimate use is for types with internal locking that are provably thread-safe.

## Common Diagnostics

| Diagnostic | First check | Smallest safe fix |
|---|---|---|
| `Main actor-isolated ... cannot be used from a nonisolated context` | Is this truly UI-bound? | Isolate the caller to `@MainActor` or use `await MainActor.run { ... }` only when main-actor ownership is correct. |
| `Actor-isolated type does not conform to protocol` | Must the requirement run on the actor? | Prefer isolated conformance first; use `nonisolated` only for truly nonisolated requirements. |
| `Sending value of non-Sendable type ... risks causing data races` | What boundary is being crossed? | Keep access inside one actor, or transfer immutable/value data instead. |
| `wait(...) is unavailable from asynchronous contexts` | Is this legacy async test waiting? | Replace with Swift Testing or async-native waiting patterns. |
| SwiftLint concurrency warnings | Is the rule exposing a real issue or just syntax drift? | Prefer a real fix; never add fake awaits to silence lint. |

## Smallest Safe Fixes

Prefer changes that preserve behavior while satisfying data-race safety:

- UI-bound state: isolate the type or member to `@MainActor`.
- Shared mutable state: move it behind an `actor`, or use `@MainActor` only if the state is UI-owned.
- Background work: when work must hop off caller isolation, use an `async` API marked `@concurrent`; when work can safely inherit caller isolation, use `nonisolated` without `@concurrent`.
- Sendability issues: prefer immutable values and explicit boundaries over escape hatches.

## Verification Checklist

When changing concurrency code:

1. Re-check build settings before interpreting diagnostics.
2. Build and clear one category of errors before moving on.
3. Run tests, especially actor-, lifetime-, and cancellation-sensitive tests.
4. Verify deallocation and cancellation behavior for long-lived tasks.
5. Use Instruments for performance claims instead of guessing.


## Output Format

Organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

Example output:

### DataLoader.swift

**Line 18: Actor reentrancy – state may have changed across the `await`.**

```swift
// Before
actor Cache {
    var items: [String: Data] = [:]

    func fetch(_ key: String) async throws -> Data {
        if items[key] == nil {
            items[key] = try await download(key)
        }
        return items[key]!
    }
}

// After
actor Cache {
    var items: [String: Data] = [:]

    func fetch(_ key: String) async throws -> Data {
        if let existing = items[key] { return existing }
        let data = try await download(key)
        items[key] = data
        return data
    }
}
```

**Line 34: Use `withTaskGroup` instead of creating tasks in a loop.**

```swift
// Before
for url in urls {
    Task { try await fetch(url) }
}

// After
try await withThrowingTaskGroup(of: Data.self) { group in
    for url in urls {
        group.addTask { try await fetch(url) }
    }

    for try await result in group {
        process(result)
    }
}
```

### Summary

1. **Correctness (high):** Actor reentrancy bug on line 18 may cause duplicate downloads and a force-unwrap crash.
2. **Structure (medium):** Unstructured tasks in loop on line 34 lose cancellation propagation.

End of example.


## References

- `references/hotspots.md` - Grep targets for code review: known-dangerous patterns and what to check for each.
- `references/new-features.md` - Swift 6.2 changes that alter review advice: default actor isolation, isolated conformances, caller-actor async behavior, `@concurrent`, `Task.immediate`, task naming, and priority escalation.
- `references/actors.md` - Actor reentrancy, shared-state annotations, global actor inference, and isolation patterns.
- `references/structured.md` - Task groups over loops, discarding task groups, concurrency limits.
- `references/unstructured.md` - Task vs Task.detached, when Task {} is a code smell.
- `references/cancellation.md` - Cancellation propagation, cooperative checking, broken cancellation patterns.
- `references/async-streams.md` - AsyncStream factory, continuation lifecycle, back-pressure.
- `references/bridging.md` - Checked continuations, wrapping legacy APIs, `@unchecked Sendable`.
- `references/interop.md` - Migrating from GCD, `Mutex`/locks, completion handlers, delegates, and Combine.
- `references/bug-patterns.md` - Common concurrency failure modes and their fixes.
- `references/diagnostics.md` - Strict-concurrency compiler errors, protocol conformance fixes, and likely remedies.
- `references/testing.md` - Async test strategy with Swift Testing, race detection, avoiding timing-based tests.
