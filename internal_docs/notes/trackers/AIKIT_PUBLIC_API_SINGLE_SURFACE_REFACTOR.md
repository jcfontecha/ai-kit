# AIKit Public API: Single-Surface Refactor (Delete `AIKitCore` Module)

Date: 2025-12-29  
Status: Draft → Approved-by-owner → Execute  
Owner: repo maintainers (Codex executes)  

This document is intentionally **extremely detailed** and is meant to survive context compaction. It is the source of truth for:

- Why the current public API boundary is failing in practice.
- What we will change (architecture) to prevent recurrence.
- A **step-by-step, validation-driven** refactor tracker that **must not regress test parity or coverage**.

---

## Table of contents

1. [Problem statement](#1-problem-statement)  
2. [What we tried (and why it failed)](#2-what-we-tried-and-why-it-failed)  
3. [Decision: “no-import” enforcement strategy](#3-decision-no-import-enforcement-strategy)  
4. [Proposed architecture (extreme detail)](#4-proposed-architecture-extreme-detail)  
5. [Refactor plan: TDD-first, validation-gated tracker](#5-refactor-plan-tdd-first-validation-gated-tracker)  
6. [Parity documentation strategy (AIKit ⇄ AI SDK mapping)](#6-parity-documentation-strategy-aikit--ai-sdk-mapping)  
7. [Definition of done (non-negotiables)](#7-definition-of-done-non-negotiables)  
8. [Appendices](#8-appendices)  

---

## 1. Problem statement

### 1.1 The intent (originally)

The original intent was:

- `AIKitCore`: stay **close to the vendored AI SDK** semantics and tests (translation engine).
- `AIKit`: provide **Apple-like** ergonomic façades (the “only import” for app developers).
- `AIKitProviders`: provider protocols + shared wire types.

This intent is documented in:

- `internal_docs/notes/proposals/AIKIT_PROPOSAL.md`
- `internal_docs/notes/proposals/AIKIT_APPLELIKE_API_PROPOSAL.md`

### 1.2 The reality (today)

Today, `Sources/AIKit/AIKit.swift` uses:

- `@_exported import AIKitCore`
- `@_exported import AIKitProviders`
- Many `public typealias X = AIKitCore.X`

That has two practical consequences:

1) **There is no true public boundary.**  
Users import `AIKit` and get almost everything from `AIKitCore` and `AIKitProviders` in autocomplete, so “AIKit is the curated surface” becomes untrue by construction.

2) **The project is stuck in a loop** (reported multiple times by the maintainer):

- We remove `@_exported import AIKitCore` to stop the leak.
- Something doesn’t build because app code (or examples/tests) were depending on “leaked” types.
- An agent “patches” by importing `AIKitCore` directly (which is worse: it cements `AIKitCore` as public API).
- We complain about apps importing `AIKitCore`.
- Another agent “fixes” it by re-adding `@_exported import AIKitCore`.
- We are back where we started.

This is not a one-off; it is a **structural failure mode**: a policy (“don’t import AIKitCore”) is being enforced only socially, not technically.

### 1.3 What must be true (new requirement)

We want a design that is intentionally safe from recurrence:

- **No one can import `AIKitCore`**, because it does not exist as an importable module.
- The parity engine remains parity-first, but it lives **inside** the public module (as internal implementation).
- Test parity and coverage are **non-negotiable**.

---

## 2. What we tried (and why it failed)

### 2.1 “Stop the leak” only (remove `@_exported import AIKitCore`)

**Attempt:** Remove `@_exported import AIKitCore` (and/or `AIKitProviders`) from `AIKit` and rely on curated re-exports.

**Why it fails in practice:**

- The curated surface is incomplete (or drifts), so downstream code breaks.
- Agents under time pressure choose the easiest fix: `import AIKitCore`.
- That “fix” makes the boundary worse than the leak: it creates explicit coupling to the parity engine module.

**Key lesson:** A social rule will not hold under repeated iteration. We need a hard boundary.

### 2.2 “Keep two layers but hide via products” (don’t vend an `AIKitCore` product)

Even if `AIKitCore` is not a standalone product, as long as `AIKit` depends on it, the module is built and can be imported transitively.

**Key lesson:** “Not a product” does not prevent `import` when the module is a transitive dependency.

### 2.3 “Use access control (`package`) to discourage usage”

Swift’s `package` access can reduce what’s visible from `AIKitCore`, but it does **not** prevent importing the module.

Also: `AIKit` currently publicly exposes many `AIKitCore` types via `typealias`. That is incompatible with `package`-izing `AIKitCore` anyway.

**Key lesson:** `package` is useful after we unify modules, but it cannot solve the “don’t import module” problem by itself.

---

## 3. Decision: “no-import” enforcement strategy

### Decision

We will **delete `AIKitCore` as a module**.

Concretely:

- Remove the `AIKitCore` SwiftPM target.
- Move `Sources/AIKitCore/**` into `Sources/AIKit/**` (keeping parity-oriented folder structure internally).
- Update all code/tests to reference `AIKit` (and `AIKitProviders`) instead of `AIKitCore`.

### Why this is different (and not “the same stop-the-leak step again”)

This approach is not a policy; it is enforcement:

- The “escape hatch” module (`AIKitCore`) is gone.
- No agent can “patch” by importing it, because it won’t compile.
- The only way forward is to fix the actual public surface (which is what we want).

---

## 4. Proposed architecture (extreme detail)

### 4.1 Products and their responsibilities (post-refactor)

#### `AIKit` (the only app-facing import)

Contains:

- `generateText` / `streamText`
- tool loop + approvals + stop conditions
- outputs (`OutputSpec`, `Output`, `ObjectSchema`, parsing)
- chat session stack (`ChatSession`, `ChatStore`, remote transport helpers)
- end-user errors (`NoObjectGeneratedError`, etc.)
- (optionally) re-export of `AIKitProviders` to keep “one import” ergonomics

**Rule:** App code should be able to do everything from `import AIKit` for typical use cases.

#### `AIKitProviders` (provider authoring surface)

Contains:

- protocols: `LanguageModel`, `ImageModel`, `EmbeddingModel`, `SpeechModel`, `TranscriptionModel`, `HTTPTransport`
- request/response types: `ModelRequest`, `ModelResponse`, `ModelStreamPart`, `ModelMessage`, `Usage`, `FinishReason`, …
- `JSONValue`, `JSONSchema`, and provider metadata/options maps
- shared helper utilities that providers need (SSE parsing stays provider-specific unless it’s truly shared)
- **`AIKitError` (moved here)** because provider modules currently throw it (and must not depend on `AIKit`)

**Rule:** Provider modules must not need to import `AIKit`.

#### Provider modules (`AIKitOpenRouter`, `AIKitOpenAI`, `AIKitFal`, `AIKitReplicate`)

Contain:

- provider factories + settings types + model implementations
- depend on `AIKitProviders` (and *not* on `AIKitCore`, which will not exist)

#### `AIKitElements` (UI components)

No architectural change required, but it must keep compiling after imports update.

#### `AIKitMacro` / `AIKitMacros`

No architectural change required, but it must keep compiling and its generated schema story must remain “single canonical representation”:

- `ObjectSchema<T>` wrapping provider-facing `JSONSchema`

### 4.2 Package.swift target graph (post-refactor)

**Targets (expected):**

- `AIKitProviders` (unchanged target)
- `AIKit` (now contains former `AIKitCore` code + current `AIKit` façade code)
- Providers: `AIKitOpenRouter`, `AIKitOpenAI`, `AIKitFal`, `AIKitReplicate` (update imports/deps)
- `AIKitElements` (unchanged dependency on `AIKit`)
- `AIKitTestKit` (update dependency to `AIKit` (+ optionally `AIKitProviders`))
- Tests: rename optional; but at minimum update test target dependencies so the same test suites run

**Non-goal:** introduce extra “CoreInternal” targets. That would recreate the same import leak risk.

### 4.3 Hard import rules (post-refactor)

This is the “loop prevention” policy, backed by the fact that `AIKitCore` won’t exist.

**Apps (recommended default):**

- `import AIKit`
- `import AIKitOpenRouter` / other provider module

**Provider modules (must):**

- `import AIKitProviders`
- Must not import `AIKit` unless explicitly justified (and documented) as “provider needs core helpers” (avoid this).

**Forbidden everywhere (enforced by compilation):**

- `import AIKitCore`

### 4.4 Public API surface design rules

#### Rule A: there is exactly one canonical “app API module”

- `AIKit` is the only module that app code should need.

#### Rule B: provider authoring is explicit

- Provider authors import `AIKitProviders` (and optionally `AIKit` if they want higher-level helpers, but it should not be required).

#### Rule C: no “shadow public API”

- Do not keep “old names” around as unused wrappers or “temporary” types. Any API that remains must be:
  - used by tests and/or docs, and
  - intentionally part of v0’s surface.

#### Rule D: if something is “advanced”, gate it

- Prefer `@_spi(Advanced)` for intentionally unstable/advanced surfaces.
- Avoid making internals public “just to make something compile”.

### 4.5 API tiering (what is Stable vs Advanced vs Internal)

This refactor is primarily structural, but we must be explicit about tiers to avoid recreating “shadow APIs”.

**Stable (documented, supported) — expected to be used by apps**

- `generateText` / `streamText` (+ `GenerateTextOptions`, `StreamTextOptions`, results, finish events)
- Tools: `ToolRegistry`, `ToolID`, `ToolSpec`, `ToolContext`, `ToolExecution`, `ToolProgress`, approvals types
- Outputs: `OutputSpec`, `Output`, `ObjectSchema`, `SchemaProviding`
- Chat (app-level): `ChatStore` (SwiftUI/Combine) + `ChatMessage` model
- Errors: `AIKitError`, `NoObjectGeneratedError`, `NoImageGeneratedError`, tool call/repair errors

**Advanced (SPI) — supported for power-users and internal integration**

These are allowed to exist, but must be:

- marked `@_spi(Advanced)` and
- called out in docs as “Advanced”.

Examples (current candidates, subject to adjustment):

- `ChatSession` and its remote-transport injection types (`ChatSessionInit`, `ChatTransport`, `AIUIMessageStreamClient`, etc.)
- low-level streaming transforms (`StreamTextTransform`) and raw-part emission knobs
- internal “repair”/parsing hooks beyond the public policy

**Internal (not intended for consumers)**

- parsing reducers and translation helpers (e.g. `parseToolCall`, internal state machines)
- any helper types created purely for parity implementation

Important note for tests:

- Many test suites currently use `@testable @_spi(Advanced)` to validate internal behavior and parity-driven edge cases.
- After the refactor, those tests should switch to `@testable @_spi(Advanced) import AIKit` and continue to validate internals without making them public.

### 4.6 Internal code organization inside `AIKit` (parity-preserving)

We still want the parity engine to be obvious.

Inside `Sources/AIKit`, we will keep a structure that mirrors the old `AIKitCore` layout and maps back to the AI SDK:

- `Sources/AIKit/Generation/*` (from `AIKitCore/Generation/*`)
- `Sources/AIKit/Streaming/*`
- `Sources/AIKit/Tools/*`
- `Sources/AIKit/Output/*`
- `Sources/AIKit/ChatSession/*`
- `Sources/AIKit/Agent/*`
- `Sources/AIKit/ControlFlow/*`
- `Sources/AIKit/Schema/*`
- `Sources/AIKit/Errors/*`
- `Sources/AIKit/Types/*`

Optionally, add a “parity namespace” pattern for helpers (not public):

- `Sources/AIKit/Internal/_AISDK/*`
- `internal enum _AISDK {}` used purely as a namespace for translation helpers (optional; prefer only if it materially improves navigation).

### 4.7 File migration map (mechanical move; behavior must not change)

We will migrate every file under `Sources/AIKitCore/**` into `Sources/AIKit/**` while preserving the internal folder structure.

See Appendix D for the complete current file list and the 1:1 destination mapping.

### 4.8 Documentation posture (post-refactor)

We will document `AIKit` as “the SDK”, and `AIKitProviders` as “provider authoring”.

Required doc updates:

- `README.md`: imports, products, platform requirements must match `Package.swift`.
- `content/docs/**`: references to “AIKitCore product” must be removed or updated.
- Ensure `content/docs/00-introduction/03-status-and-parity.mdx` explicitly states the new layout:
  - parity engine is now “internal implementation inside AIKit”, not a separate module.

### 4.9 Public API docs requirements (post-refactor)

Because this refactor removes an entire module boundary, we must not leave the new “single surface” undocumented.

Minimum required doc changes:

- Update the “import story” everywhere:
  - Prefer `import AIKit` in app-facing docs and examples.
- Mention `AIKitProviders` only in “provider authoring” documentation.
- Ensure every *Stable* entry point has at least a short doc section:
  - `generateText`, `streamText`
  - tools (tool registry + approvals)
  - outputs/schemas/macros
  - chat store/session (and which is recommended)

---

## 5. Refactor plan: test-gated, validation-driven tracker

### 5.0 Invariants (before touching anything)

- **No behavior change.** Only architectural moves + API boundary enforcement.
- **No test regression.** We do not delete tests; we only move/rename them as needed.
- **Always run the full suite frequently.** Small incremental steps; do not “big bang” without checkpoints.

### 5.1 Baseline capture (must be recorded)

- [ ] **Run full tests**: `swift test`
  - Validation: exit code 0.
  - Artifact: paste full output into a temporary log or reference in PR description.
- [ ] **Inventory the current public surfaces** (symbol graph)
  - Command: `swift package dump-symbol-graph --minimum-access-level public`
  - Validation: capture symbol graphs for `AIKit`, `AIKitCore`, `AIKitProviders`, and provider modules.
  - Goal: enable “API diff” verification after refactor.
- [ ] **Freeze scope**: confirm we are not changing feature parity in this refactor.

### 5.2 Test-gated refactor strategy (this is not “new-feature TDD”)

This refactor is intentionally **behavior-preserving**. We should not be adding “new behavior tests”.

Instead, the parity suite that already exists in `Tests/**` is the spec, and we use it as a **hard gate** while we change module topology.

The loop for this refactor is:

1) **Create new API surface** (in `AIKit`) that tests will compile against.  
2) **Update tests to consume only the new surface** (imports + target deps).  
3) **Run tests** and accept that compilation fails initially (red).  
4) **Migrate implementation** incrementally until compilation and tests are green.  
5) **Delete old surface** (`AIKitCore` module + any bridging code) only when green.  

We do not skip step (2). Tests are our enforcement mechanism:

- If the entire parity suite compiles and passes without `AIKitCore`,
- then apps cannot “accidentally” patch by importing `AIKitCore` (because it won’t exist).

**Allowed test changes:**

- Updating imports/targets to point at `AIKit`
- Renaming/moving test folders if needed by SwiftPM
- Any minor changes required to keep assertions identical after module qualification changes

**Forbidden test changes:**

- Deleting tests (coverage regression)
- Weakening assertions or deleting snapshots
- “Fixing” failures by changing expected behavior (unless we can cite a parity bug and update both Swift tests and AI SDK reference accordingly — out of scope for this refactor)

### 5.3 Tracker: step-by-step with explicit validation criteria

#### Phase 1 — Create the unified `AIKit` implementation surface (while `AIKitCore` still exists)

Important nuance:

- Today, many tests depend on **internal** symbols of the parity engine via `@testable @_spi(Advanced) import AIKitCore` (for example: `parseToolCall`, reducers, remote transport internals).
- Therefore, we cannot simply switch tests to `import AIKit` until those symbols actually live in the `AIKit` module.

So the first concrete work is: **move implementation into `AIKit`** (or stage it there) so tests can target it.

Goal: `AIKit` contains (or can compile) all implementation that used to be in `AIKitCore`.

- [ ] Create destination folder structure under `Sources/AIKit/` (matching Appendix D).
  - Validation: tree exists and matches the subsystem layout in section 4.6.
- [ ] Move (or copy, temporarily) `Sources/AIKitCore/**` → `Sources/AIKit/**`.
  - Validation: there is a 1:1 mapping for every file in Appendix D.
  - Validation: no behavior edits during the move (only import/module name fixes as required).
- [ ] Update imports within moved files:
  - Replace `import AIKitProviders` as needed (likely unchanged).
  - Replace any `import AIKitCore` self-import patterns (should not exist in AIKitCore, but ensure none remain).
  - Validation: `rg -n "\\bAIKitCore\\b" Sources/AIKit` finds no code references besides historical comments that are explicitly about the refactor.
- [ ] Ensure `AIKit` target compiles (even if tests still fail):
  - Command: `swift test` (or `swift build` if test failures are too noisy early).
  - Validation: compilation progresses; failures are now “expected due to duplicate/conflicting definitions” or unresolved references we will address next.

Checkpoint validation for Phase 1:

- We can build the package far enough that the next phase (switch tests) is meaningful.

#### Phase 2 — Switch tests to import `AIKit` (tests become the enforcement boundary)

Goal: tests should be written as if `AIKitCore` does not exist.

- [ ] Update **test target dependencies**:
  - Rename `AIKitCoreTests` → `AIKitTests` (recommended to avoid stale naming).
  - At minimum: ensure the test target depends on `AIKit` (and `AIKitTestKit`, `AIKitProviders` as needed).
  - Validation: `swift test` begins compiling the test target against `AIKit`.
- [ ] Update **test imports**:
  - Replace `@testable @_spi(Advanced) import AIKitCore` → `@testable @_spi(Advanced) import AIKit`.
  - Validation: `rg -n "import AIKitCore" Tests` returns nothing.
- [ ] Update **AIKitTestKit** (internal test utilities) dependencies/imports:
  - It must compile against `AIKit` (and `AIKitProviders` only if needed).
  - Validation: `swift test` compiles `AIKitTestKit` target.

Checkpoint validation for Phase 2:

- `swift test` should compile as far as possible; any failures must be “expected missing symbols” we will provide via the refactor.

#### Phase 3 — Remove façade typealias bridging (force real symbols in `AIKit`)

Goal: `AIKit` should define (or directly contain) the types it exposes; it should not be a thin `typealias` layer over a different module.

- [ ] In `Sources/AIKit/AIKit.swift`:
  - Remove `public typealias X = AIKitCore.X` patterns (replace with direct usage once types move).
  - Remove `@_exported import AIKitCore` (eventually).
  - Keep (or decide) `@_exported import AIKitProviders` based on the “one import” goal.
  - Validation: `swift test` still compiles enough to proceed (it may be red here).

Checkpoint validation for Phase 3:

- The build should now *force* us to migrate types rather than rely on typealias leak.

#### Phase 4 — Make the package graph stop building `AIKitCore`

Once tests are importing `AIKit`, we must ensure that `AIKitCore` is no longer a transitive dependency that can accidentally be imported.

- [ ] Update `Package.swift` so `AIKit` no longer depends on `AIKitCore`.
  - Validation: `swift test` still builds (with `AIKit` compiling all core code).
- [ ] Ensure no remaining file imports `AIKitCore`.
  - Validation: `rg -n "import AIKitCore" Sources Tests` returns nothing.

#### Phase 5 — Provider modules: remove `AIKitCore` dependency entirely

Goal: no provider module imports `AIKitCore` (and no provider module requires `AIKit`).

- [ ] Move `AIKitError` into `AIKitProviders` (providers currently throw it).
  - Validation: `AIKitOpenAI`, `AIKitFal`, `AIKitReplicate` compile with only `import AIKitProviders`.
- [ ] Update provider modules to remove `import AIKitCore`.
  - Validation: `rg -n "import AIKitCore" Sources/AIKitOpenAI Sources/AIKitOpenRouter Sources/AIKitFal Sources/AIKitReplicate` returns nothing.
- [ ] Update `Package.swift` target dependencies for provider modules:
  - Remove `AIKitCore` from `AIKitOpenAI`, `AIKitOpenRouter`, `AIKitFal`, `AIKitReplicate` target dependencies.
  - Validation: `swift test` builds provider modules without compiling `AIKitCore`.

#### Phase 6 — Delete the `AIKitCore` target

This happens only when:

- `swift test` is green,
- and nothing imports `AIKitCore`.

Steps:

- [ ] Update `Package.swift`:
  - Remove the `AIKitCore` target
  - Update `AIKit` target dependencies (it should depend directly on `AIKitProviders`)
  - Update test target dependencies
- [ ] Delete `Sources/AIKitCore/` directory (after code is moved)
- [ ] Run `swift test`
  - Validation: green.

#### Phase 7 — API + docs cleanup (no dead surface)

- [ ] Remove stale docs that mention `AIKitCore` as a product or import path.
  - Validation: `rg -n \"AIKitCore\" README.md content/docs internal_docs` returns only historically-relevant internal notes (or is intentionally updated).
- [ ] Ensure platform requirements match the package manifest.
  - Validation: `README.md` and `content/docs/00-introduction/01-installation.mdx` match `Package.swift`.
- [ ] Re-run public symbol graphs and diff against baseline:
  - Validation: `AIKit` public symbols are at least a superset of the intentionally curated ones.
  - Validation: no stray “deprecated bridge” types remain.

---

## 6. Parity documentation strategy (AIKit ⇄ AI SDK mapping)

AI SDK parity remains a priority. Since we are removing the module boundary, we must keep parity mapping obvious through **structure + comments**.

### 6.1 File header convention (required for translated internals)

Every translated internal implementation file (not pure API façade types) should include a short header comment:

```swift
// AI SDK parity:
// - Source: vendored/ai-sdk/packages/ai/src/.../<file>.ts
// - Tests:  vendored/ai-sdk/packages/ai/src/.../<file>.test.ts (or equivalent)
// - Notes:  Any intentional deviation (with reason)
```

Rules:

- Keep it short (3–6 lines).
- Do not add these headers to “pure public façade” files that aren’t direct translations.

### 6.2 Internal namespaces (optional but allowed)

If navigation becomes messy, introduce a single internal namespace type:

- `internal enum _AISDK {}` (or `_Parity`)

Use it to group translation helpers that do not belong on the public types.

### 6.3 Test parity enforcement (required)

We do not “trust” ourselves to preserve parity. We preserve parity by:

- keeping the translated test suites in Swift (`Tests/**`) mapped to the vendored AI SDK tests,
- and keeping the trackers up-to-date:
  - `internal_docs/notes/ai-sdk/AI_SDK_TESTS_RAMPUP.md`
  - `internal_docs/notes/trackers/AIKIT_USECHAT_TRACKER.md`

This refactor must not delete or weaken any test suite.

---

## 7. Definition of done (non-negotiables)

This refactor is “done” only when all are true:

1) `swift test` is green (all test targets).
2) `AIKitCore` cannot be imported because it no longer exists as a module/target.
3) `rg -n "import AIKitCore" Sources Tests` returns nothing (excluding vendored).
4) Test parity is unchanged:
   - No test files deleted.
   - No snapshot coverage reduced.
5) Docs match reality:
   - `README.md` + `content/docs/**` match `Package.swift` product names and platform requirements.
6) No dead surface:
   - No unused public wrappers kept “just in case”.
   - Any remaining `@_spi(Advanced)` usage is intentional and documented.

---

## 8. Appendices

### Appendix A — Current “AIKit” top-level public symbols (baseline reference)

From the symbol graph at the time of writing (2025-12-29), `AIKit` exposes at top-level:

- `ChatStore`
- `generateImage(...)`
- `Agent`, `AgentCall`
- `generateText`/`streamText` option/result/event types (mostly via typealias)
- tools/types/errors output/schema types

This appendix is intentionally not a full symbol dump; the baseline symbol graphs should be captured before starting (see Phase 5.1).

### Appendix B — Existing internal design docs that must remain consistent

- `internal_docs/notes/proposals/AIKIT_PROPOSAL.md`
- `internal_docs/notes/proposals/AIKIT_APPLELIKE_API_PROPOSAL.md`
- `internal_docs/notes/ai-sdk/AI_SDK_TESTS_RAMPUP.md`
- `internal_docs/notes/trackers/AIKIT_USECHAT_TRACKER.md`
- `internal_docs/notes/translation/AIKIT_USECHAT_TRANSLATION.md`

### Appendix C — Grep commands we will use as hard gates

These are “go/no-go” gates during execution:

- `rg -n "import AIKitCore" Sources Tests`
- `rg -n "\\bAIKitCore\\b" Sources Tests` (to catch typealiases, comments, docs)
- `swift test`

### Appendix D — Complete `AIKitCore` file list (must be migrated 1:1)

Current `Sources/AIKitCore/**` Swift files (as of 2025-12-29):

- `Sources/AIKitCore/AIKitCore.swift` → `Sources/AIKit/AIKitCore.swift` (or removed if empty namespace)
- `Sources/AIKitCore/Agent/ToolLoopAgent.swift` → `Sources/AIKit/Agent/Agent.swift`
- `Sources/AIKitCore/ChatSession/ChatAutoSubmitPredicates.swift` → `Sources/AIKit/ChatSession/ChatAutoSubmitPredicates.swift`
- `Sources/AIKitCore/ChatSession/ChatDraftMessage.swift` → `Sources/AIKit/ChatSession/ChatDraftMessage.swift`
- `Sources/AIKitCore/ChatSession/ChatMessage.swift` → `Sources/AIKit/ChatSession/ChatMessage.swift`
- `Sources/AIKitCore/ChatSession/ChatMessageStreamingReducer.swift` → `Sources/AIKit/ChatSession/ChatMessageStreamingReducer.swift`
- `Sources/AIKitCore/ChatSession/ChatRequestTrigger.swift` → `Sources/AIKit/ChatSession/ChatRequestTrigger.swift`
- `Sources/AIKitCore/ChatSession/ChatSession.swift` → `Sources/AIKit/ChatSession/ChatSession.swift`
- `Sources/AIKitCore/ChatSession/ChatSessionSnapshot.swift` → `Sources/AIKit/ChatSession/ChatSessionSnapshot.swift`
- `Sources/AIKitCore/ChatSession/ChatSessionStatus.swift` → `Sources/AIKit/ChatSession/ChatSessionStatus.swift`
- `Sources/AIKitCore/ChatSession/ChatSessionUpdateBroadcaster.swift` → `Sources/AIKit/ChatSession/ChatSessionUpdateBroadcaster.swift`
- `Sources/AIKitCore/ChatSession/ConvertToModelMessages.swift` → `Sources/AIKit/ChatSession/ConvertToModelMessages.swift`
- `Sources/AIKitCore/ChatSession/RemoteTransport/AIUIChatEndpointTransport.swift` → `Sources/AIKit/ChatSession/RemoteTransport/AIUIChatEndpointTransport.swift`
- `Sources/AIKitCore/ChatSession/RemoteTransport/AIUIMessage.swift` → `Sources/AIKit/ChatSession/RemoteTransport/AIUIMessage.swift`
- `Sources/AIKitCore/ChatSession/RemoteTransport/AIUIMessageDecoder.swift` → `Sources/AIKit/ChatSession/RemoteTransport/AIUIMessageDecoder.swift`
- `Sources/AIKitCore/ChatSession/RemoteTransport/AIUIMessageEncoder.swift` → `Sources/AIKit/ChatSession/RemoteTransport/AIUIMessageEncoder.swift`
- `Sources/AIKitCore/ChatSession/RemoteTransport/AIUIMessageStreamClient.swift` → `Sources/AIKit/ChatSession/RemoteTransport/AIUIMessageStreamClient.swift`
- `Sources/AIKitCore/ChatSession/RemoteTransport/AIUIMessageStreamPart.swift` → `Sources/AIKit/ChatSession/RemoteTransport/AIUIMessageStreamPart.swift`
- `Sources/AIKitCore/ChatSession/RemoteTransport/ChatTransport.swift` → `Sources/AIKit/ChatSession/RemoteTransport/ChatTransport.swift`
- `Sources/AIKitCore/ChatSession/RemoteTransport/SSEUIMessageStreamDecoder.swift` → `Sources/AIKit/ChatSession/RemoteTransport/SSEUIMessageStreamDecoder.swift`
- `Sources/AIKitCore/ChatSession/TextStreamPart+AIUIMessageStreamPart.swift` → `Sources/AIKit/ChatSession/TextStreamPart+AIUIMessageStreamPart.swift`
- `Sources/AIKitCore/ControlFlow/PruneMessages.swift` → `Sources/AIKit/ControlFlow/PruneMessages.swift`
- `Sources/AIKitCore/ControlFlow/StopConditions.swift` → `Sources/AIKit/ControlFlow/StopConditions.swift`
- `Sources/AIKitCore/Errors/AIKitError.swift` → **MOVE TO** `Sources/AIKitProviders/…` (see Phase 5)
- `Sources/AIKitCore/Errors/NoImageGeneratedError.swift` → `Sources/AIKit/Errors/NoImageGeneratedError.swift`
- `Sources/AIKitCore/Errors/NoObjectGeneratedError.swift` → `Sources/AIKit/Errors/NoObjectGeneratedError.swift`
- `Sources/AIKitCore/Errors/ToolCallErrors.swift` → `Sources/AIKit/Errors/ToolCallErrors.swift`
- `Sources/AIKitCore/Generation/GenerateImage.swift` → `Sources/AIKit/Generation/GenerateImage.swift`
- `Sources/AIKitCore/Generation/GenerateText.swift` → `Sources/AIKit/Generation/GenerateText.swift`
- `Sources/AIKitCore/Generation/PrepareStep.swift` → `Sources/AIKit/Generation/PrepareStep.swift`
- `Sources/AIKitCore/Generation/ToolCallRepair.swift` → `Sources/AIKit/Generation/ToolCallRepair.swift`
- `Sources/AIKitCore/Output/OutputParsing.swift` → `Sources/AIKit/Output/OutputParsing.swift`
- `Sources/AIKitCore/Output/OutputSpec.swift` → `Sources/AIKit/Output/OutputSpec.swift`
- `Sources/AIKitCore/Prompt/PrepareMessages.swift` → `Sources/AIKit/Prompt/PrepareMessages.swift`
- `Sources/AIKitCore/Schema/SchemaProviding.swift` → `Sources/AIKit/Schema/SchemaProviding.swift`
- `Sources/AIKitCore/Streaming/RunToolsTransformation.swift` → `Sources/AIKit/Streaming/RunToolsTransformation.swift`
- `Sources/AIKitCore/Streaming/StreamText.swift` → `Sources/AIKit/Streaming/StreamText.swift`
- `Sources/AIKitCore/Tools/CollectToolApprovals.swift` → `Sources/AIKit/Tools/CollectToolApprovals.swift`
- `Sources/AIKitCore/Tools/ParseToolCall.swift` → `Sources/AIKit/Tools/ParseToolCall.swift`
- `Sources/AIKitCore/Tools/Tools.swift` → `Sources/AIKit/Tools/Tools.swift`
- `Sources/AIKitCore/Types/ContentPart.swift` → `Sources/AIKit/Types/ContentPart.swift`
- `Sources/AIKitCore/Types/ReasoningOutput.swift` → `Sources/AIKit/Types/ReasoningOutput.swift`
- `Sources/AIKitCore/Types/StepResult.swift` → `Sources/AIKit/Types/StepResult.swift`
- `Sources/AIKitCore/Types/SystemPrompt.swift` → `Sources/AIKit/Types/SystemPrompt.swift`

### Appendix E — Critical findings from the public API review (must not be lost)

These are not all *caused* by the module split, but they repeatedly contribute to “things don’t build → import AIKitCore” failures and must be tracked during/after this refactor:

1) **Docs vs Package.swift mismatch**
   - `Package.swift` currently targets iOS 26 / macOS 26, while `README.md` and docs claim iOS 15 / macOS 12.
   - Docs mention an `AIKitCore` product, but the manifest does not vend one.

2) **`maxRetries` for text appears documented but not applied**
   - `GenerateTextOptions.maxRetries` / `StreamTextOptions.maxRetries` exist and docs mention retries, but the current text paths do not obviously retry like `generateImage` does.

3) **`@_exported` re-exports create an unstable “shadow surface”**
   - This is the core loop problem; it must not reappear in a new form.
