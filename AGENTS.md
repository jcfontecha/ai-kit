# AIKit v2 (Swift) — Agent Notes

This repo is building **AIKit**, a Swift-first, type-safe, iOS/macOS client framework inspired by Vercel's **AI SDK**.

These notes are here to keep development consistent as the codebase grows.

## Current context

- This directory is a Git worktree.
- Current focus: `streamText` tests and streaming functionality.
- In parallel, another agent is working in `../ai-kit-v2` on `generateText`.
  - Occasionally check their progress, especially for shared types or codepaths across the two branches.

## Goals

- **Client-only**: iOS + macOS only. Avoid server-only helpers (Node-style response piping, server frameworks).
- **Swift-forward APIs**: strong typing, `Sendable` correctness, structured concurrency, minimal runtime reflection.
- **Swift-first design preference**: maximize the *appropriate* use of Swift language features (without artificial complexity) to model type-safe, intuitive behavior that minimizes runtime issues. Favor elegant, Apple-like APIs with clear organization and long-term maintainability.
- **Translation-only (no improvisation)**:
  - **NEVER** improvise implementation logic or "fill in gaps" out of the blue.
  - The agent's job is **translation**: always base behavior on the vendored AI SDK's **code + tests** (see Vendored repos section).
  - Prefer robust, precise migrations with clear traceability back to AI SDK semantics.
- **Match AI SDK semantics (JS)**
  - `generateText` / `streamText` behavior parity (multi-step tool loop, stop conditions, usage aggregation, errors).
  - **Tool loop + approvals** (“toolloopagent stuff”) is a first-class requirement.
  - Streaming supports **tool-input deltas** (OpenAI-style) and **non-delta tool inputs** (Anthropic default).
- **Type-safe schema story with one canonical representation**
  - Single source of truth: `ObjectSchema<T>` wrapping provider-facing `JSONSchema`.
  - Preferred authoring path: Swift macros (in separate package).
  - Manual escape hatch: `ObjectSchema<T>.manual(jsonSchema:name:description:)`.
  - Do **not** introduce a second schema DSL/builder.
- **Provider architecture**: pluggable providers, unified event model and request/response surfaces.
- **Test-driven**: mirror the AI SDK test taxonomy and scenarios.

## Non-goals (for now)

- Shipping “secure key storage” or production credential posture. Assume an API key can be provided directly.
- Full parity with AI SDK UI/server adapters (Response piping, framework integrations).

## Vendored repos

These repos are vendored in this repository for reference:

- `ai-sdk/`: Vercel's AI SDK (JavaScript/TypeScript). Primary reference for behavior, tests, and API semantics. Used to ensure parity with `generateText` / `streamText` behavior, tool loop implementation, and streaming event models.
- `openrouter-provider/`: OpenRouter provider implementation. Reference for provider architecture patterns and OpenRouter-specific behavior.
- `ai-elements/`: AI Elements UI components library. Reference for UI patterns and component design (when building Swift equivalents).

## Repo layout

- `Sources/AIKitCore`: orchestration + public API (generate/stream, tool loop, outputs, errors).
- `Sources/AIKitProviders`: provider protocols, wire models, JSONSchema/JSONValue, streaming event model.
- `Sources/AIKit`: convenience umbrella target (re-exports / combines).
- `Sources/AIKitTestKit`: internal test utilities (snapshots, deterministic clocks/IDs, async helpers).
- `AIKitMacros/`: separate Swift package that contains schema-authoring macros.

## Schema strategy (single way)

- Canonical schema type: `ObjectSchema<T>` (in `AIKitCore`) with provider-facing `JSONSchema` (in `AIKitProviders`).
- Macro-generated schema should always produce `ObjectSchema<T>.manual(jsonSchema:..., name: ...)` (no DSL).
- `JSONSchema` builders exist only as low-level helpers (e.g. `JSONSchema.object(...)`) for macro/manual construction.

If a change proposes a second authoring system (new DSL, builder, alternative schema type), stop and reconsider.

## Streaming + tool loop parity targets

When implementing parity, prefer small units and match AI SDK concepts:

- Streaming must model events equivalent to AI SDK’s `LanguageModelV3StreamPart`, including:
  - `text-start/delta/end`
  - reasoning deltas (if supported)
  - `tool-input-start/delta/end` (optional; providers may omit)
  - `tool-call`, `tool-result`
  - tool approval request/response
  - step boundaries + overall finish
- Tool execution pipeline must support:
  - local tools
  - dynamic tools
  - provider-executed tools (do not run locally)
  - delayed async tool results (finish must wait)
  - tool approvals that pause/resume the loop

## TDD workflow

- Strict development workflow (must follow in order):
  1. Analyze the AI SDK tests and implementation.
  2. Identify the equivalent API surface in AIKit.
  3. Reason about behavior translation from TypeScript to Swift.
  4. Write a comprehensive suite of tests.
  5. Run the tests and confirm they fail.
  6. Implement logic until tests pass.

- Tests live under `Tests/AIKitCoreTests/...` and should mirror `ai-sdk/packages/ai/src/...` scenario groupings (see Vendored repos section).
- Prefer snapshot-style assertions for complex event streams.
  - Record snapshots with `AIKIT_SNAPSHOT_RECORD=1`.
  - Snapshots are stored under `Tests/__Snapshots__/`.

Recommended incremental implementation order:
1. `OutputSpec` response formats + parsing
2. `parseToolCall`
3. `collectToolApprovals` + `pruneMessages`
4. `runToolsTransformation`
5. `generateText` (multi-step tool loop)
6. `streamText` (streaming + multi-step)
7. `ToolLoopAgent` wrapper behavior

## Local commands

- Run tests: `swift test`
- Record snapshots: `AIKIT_SNAPSHOT_RECORD=1 swift test`
- Build non-UI targets (AIKit framework/packages): `swift build`
- Build UI-dependent targets (e.g. demo apps): `xcb <target>` (example: `xcb AIKitElementsDemoApp`)

## House rules

- Keep naming clean and intentional (avoid confusing target/module proliferation).
- Avoid “mindless” churn: don’t rename/restructure without a clear, agreed reason.
- Keep APIs and tests aligned with `AIKIT_PROPOSAL.md` and the AI SDK behavior inventory in `AI_SDK_TESTS_RAMPUP.md`.
