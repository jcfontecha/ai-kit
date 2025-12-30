# AIKit Public API Consolidation (Delete Duplicate Surfaces)

Date: 2025-12-29  
Owner: Juan + Codex  
Status: **Rewrite-in-progress (source of truth)**  
Scope: **AIKit target public API only** (no behavior changes)

This document is intentionally long and explicit. It is meant to survive context compaction and be executable as a checklist.

---

## 0) Non‑negotiables (hard constraints)

1. **Behavior parity unchanged**
   - AI SDK semantics are the spec; Swift code is a translation.
   - No changes to tool loop behavior, stop conditions, usage aggregation, streaming parts semantics, approvals, etc.

2. **Test parity unchanged**
   - We do **not** delete tests.
   - We do **not** delete snapshots.
   - If tests must move to new entry points, we rewrite tests but preserve scenario coverage.

3. **Duplicate *public* entry points must be deleted, not renamed or “hidden by docs”**
   - No “workarounds” like leaving `generateText` around and telling people not to use it.
   - No thin forwarding wrappers that preserve the old entry points.

4. **Single obvious entry points**
   - If a user imports `AIKit`, there should be a single obvious starting point per capability.
   - Power is allowed, but it must be discoverable **from the canonical entry points**, not via a second parallel API.

5. **No leftovers**
   - No unused/outdated public types.
   - No orphaned docs pages.
   - No dead code after consolidation.

6. **Document new APIs**
   - Every new public API added to enable consolidation must be documented.

---

## 1) Problem statement

AIKit currently has **duplicated ways** to do the same thing:

- Text generation: `generateText(...)` (one-shot) vs `Agent.generate(...)` (configure-once loop policy)
- Text streaming: `streamText(...)` (one-shot) vs `Agent.stream(...)` (configure-once loop policy)
- Tool loop wrapper: competing “Agent protocol + Agent wrapper type” history
- Chat: `ChatSession` (engine) vs `ChatStore` (app-facing façade)

This duplication causes:

- **Ambiguous onboarding**: autocomplete shows multiple “main” ways; users don’t know what’s intended.
- **Docs drift**: docs and examples pick different entry points.
- **Maintenance drag**: every feature has to stay consistent across multiple surfaces.
- **Refactor loops**: attempts to “hide” one surface tend to fail because code doesn’t compile, and consumers “patch” by importing internal modules or reaching for the wrong layer.

We want AIKit to be designed so that:

- There is **no debate** about how to start.
- The framework is “Apple-like”: clear, typed, discoverable APIs with sensible defaults.
- Power users can still access every capability **through the canonical entry points**.

---

## 2) What we tried (and why it failed)

### 2.1 Historical loop: “two layers + export leaks”

We’ve been through this cycle before:

- Remove `@_exported import AIKitCore` to discourage importing internals.
- Something breaks or missing types aren’t exposed.
- Consumers import `AIKitCore` to patch around it (worse).
- Re-add `@_exported import AIKitCore` to fix the break.

Root cause: the public surface and internal surface were not cleanly separated by design. “Stop the leak” is not enough if the API shape still encourages reaching for internals.

### 2.2 “Hide by docs / omit from docs”

This fails because autocomplete and symbol graphs still show competing entry points.

### 2.3 “Mark old surface as SPI”

SPI helps, but it does not solve the underlying issue if:

- tests/examples/docs still use the SPI surface
- SPI becomes a de facto second public API
- the stable surface is missing power knobs

SPI is acceptable only for **explicitly advanced** integration points and must not become the primary path.

### 2.4 Anti-pattern we must avoid in this refactor: “rename as a workaround”

Renaming a duplicate entry point (e.g. `generateText` → `runGenerateText`) is not the goal.

The goal is:

- **No competing top-level entry points** in the `AIKit` module.
- The orchestration logic may exist internally, but it must be clearly an implementation detail (namespaced, internal, and not a user API).

---

## 3) Target end-state (architecture)

### 3.1 Canonical entry points (stable public API)

There are exactly three canonical entry points:

1) `generateText` / `streamText` / `generateImage` — one-shot model calls
2) `ChatStore` — chat UX state (SwiftUI/Combine-facing)
3) `Agent` — loop policy wrapper (multi-step, tool loop; maps to AI SDK’s `ToolLoopAgent`)

### 3.2 Supporting public vocabulary (required)

The canonical entry points need a vocabulary; these remain public:

- Provider protocols / wire types (via `AIKitProviders`)
- Messages, tools, approvals
- Output specs + schemas
- Stop conditions
- Result types (`GenerateTextResult`, `StreamTextResult`, streaming parts)

These are not “another way” — they are building blocks.

### 3.3 What must be deleted from stable public API

The following must **not** exist as stable public API in `AIKit`:

- Global orchestration: `generateText(...)`, `streamText(...)`, `generateImage(...)`
- Chat engine: `ChatSession` and any `ChatSession*` supporting types
- Any `Agent` protocol (only the `Agent` wrapper type remains)

### 3.4 Internal implementation structure (parity-traceable)

We keep the translation-only engine, but we make it obviously internal.

**New internal namespace layer (proposed):**

- `Sources/AIKit/Internal/Parity/` (or `Sources/AIKit/_Internal/`)
  - `GenerateTextOrchestrator.swift`
  - `StreamTextOrchestrator.swift`
  - `GenerateImageOrchestrator.swift`
  - `ChatEngine.swift` (internal engine currently called `ChatSession`)

Rules:

- Orchestrators are **internal** and **namespaced** (e.g. `enum GenerateTextOrchestrator { static func run(...) }`).
- Each orchestrator file starts with:
  - a single-line mapping comment to the AI SDK source file
  - a short list of AI SDK tests that define behavior

Example header comment (private/internal code only):

```swift
// Parity: vendored/ai-sdk/packages/ai/src/generate-text/generate-text.ts
// Tests: vendored/ai-sdk/packages/ai/src/generate-text/generate-text.test.ts
```

This is how we make parity “painfully obvious” without exposing duplicate public API.

---

## 4) Proposed public API (extreme detail)

This section defines exactly what we want users to see and use.

### 4.1 `generateText` / `streamText` (canonical)

Design goals:

- Minimal boilerplate for common use.
- Strong typing for outputs.
- Power knobs remain available via `GenerateTextOptions` / `StreamTextOptions`.
- Configure-once and loop policy lives on `Agent`.

#### 4.1.1 Minimal path

```swift
let result = try await generateText(.init(
  model: model,
  prompt: "Hello",
  output: Output.text()
))

let stream = streamText(.init(
  model: model,
  prompt: "Hello",
  output: Output.text()
))
for try await delta in stream.textStream { ... }
```

#### 4.1.2 Typed output path

```swift
let result = try await generateText(.init(
  model: model,
  prompt: "Give JSON",
  output: Output.json()
))
let value = try result.output
```

### 4.2 `Agent` (canonical power surface)

Design goal: `Agent` is the *explicit* advanced surface for multi-step + hooks. It’s okay if the initializer is big, but we must make it readable.

#### 4.2.1 Required shape

- Only `public struct Agent<CallOptions, OutputSpec>`
- No public `Agent` protocol

#### 4.2.2 Group advanced options to keep the initializer sane

Instead of 30 parameters, group into nested structs:

- `Agent.Defaults` (model/system/tools/settings/etc.)
- `Agent.LoopPolicy` (stopWhen/maxRetries/prepareStep/repairToolCall)
- `Agent.StreamingHooks` (includeRawParts/transform/callbacks)

This keeps the public API powerful but readable.

### 4.3 `ChatStore` (canonical chat)

Design goal: `ChatStore` is the only user-facing chat driver.

Rules:

- No public signatures mention `ChatSession` or any `ChatSession*` types.
- Remote customization happens via `ChatStore.RemoteConfiguration`.
- If there is a need for custom transports, that is `@_spi(Advanced)` and not documented as the primary path.

---

## 5) Refactor approach (TDD + validation gates)

We will do this as a strict sequence. The goal is to keep the repo green and make every step verifiable.

### 5.1 Golden rule: we never change behavior while changing API

If a test fails, we must diagnose:

- Did we lose a configuration knob when moving to the canonical entry point?
- Did we accidentally change ordering/timing semantics?
- Did we accidentally remove an internal hook used by tests?

We do **not** “fix” failures by changing behavior unless the failure reveals a pre-existing bug and we can prove it against AI SDK behavior.

### 5.2 Validation toolbox (used repeatedly)

- **Search gates**
  - `rg -n "\\b(generateText|streamText|generateImage|ChatSession)\\b" -S Sources Tests E2E Examples content`

- **Public surface gates**
  - `swift package dump-symbol-graph --minimum-access-level public > .analysis/symbolgraphs/<phase>/AIKit.json`

- **Correctness gates**
  - `swift test`
  - `xcb demo-swiftui`
  - `xcb demo-macos`

---

## 6) SUPER THOROUGH tracker (step-by-step)

This is the executable checklist.

### Phase 0 — Baseline (capture “before”)

0.0 Ensure working tree is clean or changes are intentionally staged for this refactor.

0.1 Capture symbol graph baseline

- [ ] `mkdir -p .analysis/symbolgraphs/baseline/2025-12-29`
- [ ] `swift package dump-symbol-graph --minimum-access-level public > .analysis/symbolgraphs/baseline/2025-12-29/symbolgraph.json`

0.2 Verify baseline correctness

- [ ] `swift test`
- [ ] `xcb demo-swiftui`
- [ ] `xcb demo-macos`

**Pass criteria:** baseline graph exists; tests/demos pass.

---

### Phase 1 — Create/complete canonical APIs (before deleting anything)

Goal: ensure the canonical entry points can express every capability currently exercised by tests.

1.1 Inventory “capability knobs” used by tests

- [ ] Grep for usage of old entry points and option knobs:
  - `rg -n "\\bgenerateText\\b" Tests -S`
  - `rg -n "\\bstreamText\\b" Tests -S`
  - `rg -n "includeRawParts|transform|onChunk|onError|onAbort|onFinish|prepareStep|repairToolCall|experimentalContext" Tests -S`

1.2 Decide where each knob moves

- [ ] For each knob, decide:
  - GenerateTextOptions / StreamTextOptions
  - Agent configuration
  - Agent configuration
  - ChatStore configuration

Write the final decision into this doc (update Section 4) before implementing.

1.3 Add missing canonical API (TDD)

For each missing capability:

- [ ] Add a test that uses **only the canonical entry points** (`generateText`/`streamText`/`Agent`/`ChatStore`) and asserts the same behavior.
- [ ] Run tests and see it fail.
- [ ] Implement the minimal API addition to make it pass.

**Pass criteria:** every behavior currently tested via old entry points can be expressed via canonical entry points.

---

### Phase 2 — Migrate tests to canonical entry points (TDD conversion)

Goal: tests stop using duplicate entry points while preserving scenario coverage.

2.1 GenerateText tests

- [ ] Replace one-off `Agent.generate(...)` usage with `generateText(.init(...))` where loop policy is not required.

Validation:
- [ ] `rg -n "\\bAIClient\\b" Tests -S` returns **zero** matches.
- [ ] `swift test` passes.

2.2 StreamText tests

- [ ] Replace one-off `Agent.stream(...)` usage with `streamText(.init(...))` where loop policy is not required.

Validation:
- [ ] `rg -n "\\bAIClient\\b" Tests -S` returns **zero** matches.
- [ ] `swift test` passes.

2.3 GenerateImage tests

- [ ] Prefer a single image-generation entry point (avoid parallel “wrapper” APIs).

Validation:
- [ ] `rg -n "\\bAIClient\\b" Tests -S` returns **zero** matches.
- [ ] `swift test` passes.

2.4 Chat tests

- [ ] Replace any direct `ChatSession` usage with `ChatStore` tests.
- [ ] If some tests are truly “engine” tests, move them under internal engine names and ensure they do not create a second public entry point.

Validation:
- [ ] `rg -n "\\bChatSession\\b" Tests -S` returns **zero** matches.
- [ ] `swift test` passes.

---

### Phase 3 — Delete duplicate public API surfaces (the actual deletion)

Only after Phase 2 is green.

3.1 Delete global functions (text)

- [ ] Remove the global functions from the module surface (delete them, do not rename them).
- [ ] Ensure orchestration logic is internal and namespaced (Section 3.4).

Validation:
- [ ] Public symbol graph contains no `generateText`/`streamText`.
- [ ] `swift test` passes.

3.2 Delete global functions (images)

- [ ] Remove `generateImage` global functions.

Validation:
- [ ] Public symbol graph contains no `generateImage`.
- [ ] `swift test` passes.

3.3 Delete ChatSession as a public surface

- [ ] Ensure `ChatSession` and related types are not public / not SPI.

Validation:
- [ ] Public symbol graph contains no `ChatSession*`.
- [ ] Demos build.

---

### Phase 4 — Docs/examples become single-path

4.1 Update docs

- [ ] Quickstart: only `generateText` / `streamText`
- [ ] Chat docs: only `ChatStore`
- [ ] Agent docs: only `Agent`
- [ ] Advanced docs: clearly marked, and must not reintroduce deleted entry points

Validation:
- [ ] `rg -n "\\b(AIClient|ChatSession)\\b" content/docs -S` returns **zero** matches.

4.2 Update examples + E2E

- [ ] Examples compile and use canonical entry points.
- [ ] E2E tests compile and run.

Validation:
- [ ] `swift test`
- [ ] `xcb demo-swiftui`
- [ ] `xcb demo-macos`

---

### Phase 5 — Prove the public surface is collapsed

- [ ] Capture “after” symbol graph:
  - `.analysis/symbolgraphs/after/<date>/symbolgraph.json`
- [ ] Compare baseline vs after (manual review is fine, but must be explicit):
  - Confirm removed symbols are truly gone.

**Definition of done:**

- Only canonical entry points remain.
- Tests/demos are green.
- Docs teach only one way.
- Internal parity mapping comments exist in internal namespace files.

---

## 7) Deliverables (what we will produce)

- Collapsed public API (symbol graph proves it)
- Updated docs teaching only canonical path
- Tests rewritten to use canonical entry points (no coverage loss)
- Internal parity trace comments and file organization

---

## 8) Open questions (must be answered before Phase 1)

1) Where do streaming hooks live: `Agent` only, or also `StreamTextOptions` / `StreamTextTransform`?
2) Do we treat image generation as part of this consolidation (recommended: yes, to avoid a second entry point)?
3) Which lower-level chat transport types (if any) remain stable public vocabulary vs advanced SPI?
