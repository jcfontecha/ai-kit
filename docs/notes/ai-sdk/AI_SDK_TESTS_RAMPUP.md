# AI SDK test ramp-up (ai-sdk/)

This is a quick taxonomy of what the **AI SDK** validates via tests in `ai-sdk/`, with extra depth on the parts that matter for AIKit (Swift): `generateText`, `streamText`, output schemas, and the tool-loop / tool-approval flows.

## Inventory (tests by package)

Test-file counts (by `*.test.*` / `*.spec.*` in `ai-sdk/packages/*`):

- `ai-sdk/packages/ai`: **79** (core orchestration: generate/stream, tools, telemetry, UI stream adapters)
- `ai-sdk/packages/provider-utils`: **48** (schemas, JSON parsing/repair, HTTP helpers, streaming helpers)
- Provider packages (request shaping + streaming parsers):
  - `ai-sdk/packages/openai`: **14**
  - `ai-sdk/packages/gateway`: **10**
  - `ai-sdk/packages/google-vertex`: **10**
  - `ai-sdk/packages/google`: **9**
  - `ai-sdk/packages/amazon-bedrock`: **9**
  - …many others with 1–6 tests each
- UI/framework packages:
  - `ai-sdk/packages/react`: **3**, `ai-sdk/packages/vue`: **3**, `ai-sdk/packages/svelte`: **3**, `ai-sdk/packages/angular`: **3**
- `ai-sdk/packages/codemod`: **54** (migration tooling; not relevant for AIKit runtime behavior)

There are also E2E tests under `ai-sdk/examples/ai-core/src/e2e/*.test.ts` that exercise multiple providers end-to-end (usually requiring credentials).

## Core package: `@ai-sdk/ai` (what we most care about)

## Current Focus (AIKit v2 Swift)

We are focusing on **generateText** + **streamText** parity first (client-only). UI/server adapters are out of scope for now.

### streamText parity tracking (Swift)

Status legend: ✅ done · 🟡 partial · ⏳ pending

**Core streaming surface**
- ✅ `textStream` emits only non-empty text deltas, excludes reasoning.
- ✅ `fullStream` emits text + reasoning + sources/files + tool-call/result + step boundaries + finish.
- ✅ `includeRawParts` controls `raw` emission.

**Output parsing during streaming**
- ✅ `partialOutputStream` for text/json/object/array/choice.
- ✅ `output` / `text` / `content` / `steps` / `usage` / `totalUsage` / `finishReason` aggregation.

**Tool loop & multi-step**
- ✅ Local tool execution during streaming (tool-call → tool-result).
- ✅ Tool approval request flow (needsApproval).
- ✅ Multi-step with `stopWhen` and usage aggregation.

**Callbacks & hooks**
- ✅ `onStepFinish` and `onFinish` invoked with step aggregation.
- ✅ `onChunk` semantics (all supported chunk types, pauses stream until completion).
- ✅ `onError` semantics (stream errors, gateway errors).
- ✅ `onAbort` semantics.

**Tool-input streaming + tool hooks**
- ✅ Tool input deltas forwarded in `fullStream`.
- ✅ `onInputStart` / `onInputDelta` callback coverage (tool-input-* events).
- ✅ Provider-executed tool input streaming (providerExecuted + dynamic flags preserved).

**Error + abort handling**
- ✅ Provider stream error surfaced as error chunk and finish reason.
- ✅ Abort mid-stream semantics (incl. tool execution).
- ✅ “No output generated” error path parity.

**Transform pipeline**
- ✅ `transform` stream mapping (per-chunk transforms, early termination).
- ✅ Transform effects on derived fields (`text`, `steps`, `usage`, etc).

**Provider metadata propagation**
- ✅ Provider metadata on text/reasoning/tool parts merges correctly.

Next steps: iterate top-to-bottom in this list, verifying against `ai-sdk/packages/ai/src/generate-text/stream-text.test.ts`.

### streamText remaining gaps (ranked)

Ranked by user-impact + core correctness first, then completeness with AI SDK edge cases.

1) **Response metadata + warnings parity**
   - 🟡 Now covered: response metadata fallback behavior, warnings surfaced on first step.
   - Remaining: logWarnings behavior (if we add a logger equivalent).
   - AI SDK refs: `result.fullStream` (fallback response metadata), `result.warnings`, `logWarnings`.

2) **Approval flows during streaming (full parity)**
   - ✅ approval request stops step; pre-approved tool resumes loop; provider approval request includes tool call.
   - ✅ approval after preliminary results; provider-executed approval approved/denied sequences.
   - AI SDK refs: `tool execution approval`, `provider-executed tool (MCP) approval`.

3) **Dynamic + provider-executed tools beyond simple cases**
   - ✅ dynamic tool calls/results.
   - ✅ provider-executed tools with deferred results.
   - ✅ programmatic tool calling fixtures.
   - AI SDK refs: `dynamic tools`, `provider-executed tools`, `programmatic tool calling`.

4) **Stop conditions + prepareStep matrix**
   - ✅ step inputs (assistant + tool messages in subsequent step).
   - ✅ multiple stop conditions, prepareStep model switching, prepareStep message overrides.
   - ✅ prepareStep with image URLs.
   - AI SDK refs: `2 stop conditions`, `prepareStep calls`, `step inputs`, `prepareStep with model switch and image URLs`.

5) **Result promise surface parity**
   - ✅ result.request/response, totalUsage, usage, finishReason, toolCalls/toolResults surfaces.
   - ✅ response messages surface via `StreamTextResult.responseMessages`.
   - AI SDK refs: `result.response.messages`, `result.request`, `result.response`, `result.totalUsage`, etc.

6) **Transform edge cases**
   - Missing tests for: multiple transforms, transform abort semantics in combination with multi-step.
   - AI SDK refs: `with multiple transformations`, `with transformation that aborts stream`.

7) **Mixed-content streaming order**
   - ✅ interleaving text/reasoning/tool-input deltas in complex sequences.
   - AI SDK refs: `mixed multi content streaming with interleaving parts`, `mixed text and reasoning blocks`.

8) **Errors & abort nuances**
   - ✅ reject promises on error (stream throws), abort in second step.
   - ✅ swallow error behavior, onFinish during error chunk nuances.
   - AI SDK refs: `errors`, `abort signal`.

Additional parity updates (recent):
- Mixed text+image parts: empty text parts are filtered for user and assistant messages.
- Supported URL wildcard handling: `*/*` and `image/*` URL support patterns exercised.
- File URL missing mediaType throws even if download provides a mediaType.

Out of scope (client-only):
- `pipeUIMessageStreamToResponse`, `toUIMessageStreamResponse`, Node/Response streaming adapters.

## Provider parity tracking: OpenRouter (openrouter-provider/)

Status legend: ✅ done · 🟡 partial · ⏳ pending

**API surface**
- 🟡 `createOpenRouter` provider factory + default `openrouter` instance (strict compatibility)
- 🟡 chat/completion/embedding model creation + settings types
- ⏳ full call-as-function parity (modelId overloads + completion/chat selection)

**Chat model (non-streaming)**
- 🟡 request shaping (messages, tools, toolChoice, settings, response_format)
- 🟡 HTTP 200 error payload handling (APICallError equivalent)
- 🟡 reasoning_details → reasoning parts + providerMetadata mapping
- 🟡 images (data URL → `file` output)
- 🟡 tool-call providerMetadata includes `reasoning_details` (even when empty)
- 🟡 annotations + file parser annotations parity edge cases (old/new formats)

**Chat model (streaming)**
- ✅ SSE parsing + text/reasoning/tool input/tool calls/sources/files + finish
- ✅ usage accounting + providerMetadata accumulation (incl. upstream inference cost + token details)
- ✅ stream errors as structured objects (`message/type/code/param`) via `ModelStreamError`
- ✅ reasoning ordering (reasoning before text) + reasoning_details precedence
- 🟡 response metadata ordering exactness (covered for common cases; keep validating vs upstream)

**Completion model**
- 🟡 request shaping + prompt conversion (chat→prompt format)
- ✅ streaming + usage accounting + finish metadata
- ✅ streaming error payload parity (structured errors)

**Embedding model**
- 🟡 request shaping + usage + providerMetadata cost mapping
- ⏳ edge-case error handling

**Message conversion**
- 🟡 `convertToOpenRouterChatMessages` for text/image/file/audio + cache_control
- 🟡 reasoning_details accumulation + annotations preservation
- ⏳ full test parity for cache-control/filename/URL behaviors

**Tests ported**
- 🟡 `error-response.test.ts`
- 🟡 partial `convert-to-openrouter-chat-messages.test.ts`
- 🟡 `chat/index.test.ts` (ported streaming-heavy coverage + core doGenerate cases)
- 🟡 `completion/index.test.ts` (ported streaming coverage)
- 🟡 minimal `embedding/index.test.ts`
- ✅ `tests/stream-usage-accounting.test.ts`

Next steps: finish porting the full OpenRouter provider test suite and close parity gaps listed above.

### `generateText` (multi-step tool-loop)

Primary test suite: `ai-sdk/packages/ai/src/generate-text/generate-text.test.ts` (starts at `describe('generateText')`).

Key scenarios validated:

- **Result surface area**
  - `result.content`, `result.text`, `result.reasoningText`, `result.sources`, `result.files`.
  - `result.steps`: each “step” includes content, usage, finish reason, provider metadata, etc.
  - `result.toolCalls` and `result.toolResults` extracted from the *final* step (and can be empty if the last step is plain text).
  - `result.response.messages` includes message history from all steps (assistant + tool messages).
  - `result.request` and `result.response` expose request/response metadata.

- **Tools + tool loop execution**
  - When model finishes with `finishReason=tool-calls`, the SDK:
    - parses tool calls (including validation) and executes tools;
    - appends tool results as tool messages;
    - re-calls the model for the next step until stop conditions are met.
  - Tool execution passes **context** (`options.messages`, `system`, `abortSignal`, `experimental_context`) into tool execution and callbacks.
  - `options.activeTools` filters which tools are made available to the model.
  - **Dynamic tools** (“unknown at compile time”) are supported (model can call tools not in the static map).
  - **Provider-executed tools** (e.g. MCP) are supported:
    - the SDK must NOT execute them locally;
    - they still appear as tool-call/tool-result content and in streams.

- **Stop conditions & step hooks**
  - `options.stopWhen`: supports multiple stop conditions; conditions are called per step.
  - `prepareStep`: hook to alter the next step (e.g., switch model, adjust supported URL logic, tweak prompt/tools).
  - Usage aggregation:
    - `result.usage` is final-step usage,
    - `result.totalUsage` is the sum across steps.

- **Tool-call parsing + repair**
  - Invalid tool calls are represented with an error payload (instead of throwing) and surfaced into content/response messages.
  - A `repairToolCall` hook can be invoked to fix invalid JSON / schema validation failures.

- **Tool approvals**
  - Tools can require approval (static flag or `needsApproval(input, options)`).
  - When approval is required:
    - the SDK stops after the tool-call step (`finishReason=tool-calls`);
    - it emits a `tool-approval-request` content part and includes it in response messages.
  - When approvals are later provided (as tool messages), the SDK continues:
    - approved → executes tool and continues loop,
    - denied → emits an “execution denied” result and continues loop.
  - Provider-executed tool approvals (MCP flow) are supported as a distinct pathway.

- **Tool result flavors**
  - “Preliminary results” (multiple tool-result parts) exist; tests verify only the *final* result is included where appropriate.

- **Observability**
  - `logWarnings` is called with step warnings.
  - Telemetry is **off by default**; when enabled it records:
    - model call spans,
    - tool-call spans (success + error),
    - optional inclusion/exclusion of telemetry inputs/outputs.

Companion unit tests backing the above behavior:

- `ai-sdk/packages/ai/src/generate-text/parse-tool-call.test.ts`
  - validates: no-tools/missing-tool errors, empty `{}` / empty-string inputs, provider metadata passthrough, dynamic/providerExecuted flags, repair hook semantics, “title” propagation.
- `ai-sdk/packages/ai/src/generate-text/collect-tool-approvals.test.ts`
  - validates: extracting approved/denied approvals from message history; errors for unknown approval IDs / missing tool calls.
- `ai-sdk/packages/ai/src/generate-text/to-response-messages.test.ts`
  - validates: assistant message includes tool-call parts; tool results/errors become tool messages; provider metadata mapped into providerOptions; provider-executed calls and approval requests represented.
- `ai-sdk/packages/ai/src/generate-text/run-tools-transformation.test.ts`
  - validates stream-time tool execution:
    - holds finish until delayed tool results arrive,
    - `Tool.onInputAvailable` hook is called before execution (and even when approval is required),
    - provider-emitted `tool-approval-request` is forwarded and references the correct tool call,
    - provider-executed tools are not executed locally.
- `ai-sdk/packages/ai/src/generate-text/prune-messages.test.ts`
  - validates removing reasoning and/or tool parts from message history (token pruning strategy).
- `ai-sdk/packages/ai/src/generate-text/smooth-stream.test.ts`
  - validates “chunking”/smoothing text deltas (word/line/custom); ensures buffered text flushes before tool-call parts.

### `streamText` (streaming + multi-step tool-loop)

Primary test suite: `ai-sdk/packages/ai/src/generate-text/stream-text.test.ts` (starts at `describe('streamText')`).

Key scenarios validated:

- **Streams exposed**
  - `result.textStream` emits only text deltas (filters empty deltas; excludes reasoning).
  - `result.fullStream` emits the full typed event stream, including:
    - text start/delta/end,
    - reasoning deltas,
    - sources/files,
    - tool-input streaming (`tool-input-start`, `tool-input-delta`, `tool-input-end`),
    - tool-call + tool-result events,
    - step boundaries (`start-step`, `finish-step`) and overall `finish`.

- **Tool-input streaming support**
  - Tests explicitly validate tool-call input deltas flowing through `fullStream`.
  - There are also tests for **provider-executed dynamic tools with input streaming** (providerExecuted+dynamic flags remain attached to tool-input/tool-call/tool-result events).
  - This is the crucial behavior for “OpenAI-style tool-input deltas” vs “Anthropic-style no deltas”: the core stream pipeline is built to handle both.

- **Tool execution during streaming**
  - For locally executed tools, the SDK emits tool-result events into the stream and ensures ordering (including delayed async tool results).
  - Invalid tool calls and tool execution errors are surfaced as stream parts (not thrown as uncaught exceptions).

- **Multi-step behavior**
  - Same as `generateText`, but step boundaries + final aggregation happen while streaming.
  - `options.stopWhen` + `prepareStep` + usage aggregation are validated in streaming form as well.

- **Abort/error semantics**
  - Tests cover aborting:
    - basic abort,
    - abort in later steps,
    - abort during tool call / tool execution.
  - Error handling:
    - errors in `doStream` become “error” stream parts,
    - `onError` and `onFinish` callback semantics (including mid-stream errors),
    - “consumeStream” variants that intentionally swallow certain errors.

- **Transform pipeline**
  - `options.transform` can:
    - transform chunks,
    - transform derived values (`text`, `steps`, `usage`, etc),
    - abort stream early based on content.

- **Output parsing during streaming**
  - `options.output` integrates output schema strategy into streaming:
    - text output default + explicit,
    - object/array/choice outputs with partial-output streaming and final validation.

- **UI/Response adapters**
  - A large portion validates producing UI-message streams and writing server responses (`pipeUIMessageStreamToResponse`, `toUIMessageStreamResponse`, etc).
  - For AIKit (client-only), this mostly informs **event model structure**, not HTTP server plumbing.

### Output formats (`Output.*`)

Unit tests: `ai-sdk/packages/ai/src/generate-text/output.test.ts`.

Validates:

- `Output.text`:
  - response format is plain `{ type: 'text' }`,
  - complete output parsing returns the string as-is,
  - partial output parsing yields `{ partial: string }`.
- `Output.object` / `Output.array` / `Output.choice` / `Output.json`:
  - response format is `{ type: 'json', schema: <draft-07> }` (with optional `name`/`description`),
  - complete output parsing:
    - parses JSON and validates against schema,
    - throws `NoObjectGeneratedError` on parse/validation failure,
  - partial output parsing:
    - attempts “repairable JSON” parsing,
    - returns `undefined` on unrecoverable input,
    - special-cases arrays (can return all-but-last element when last is incomplete),
    - special-cases choice output ambiguity (prefix collisions return `undefined`).

### ToolLoopAgent (agent wrapper)

Tests: `ai-sdk/packages/ai/src/agent/tool-loop-agent.test.ts`.

Validates the wrapper (not the loop mechanics themselves):

- `prepareCall` hook is invoked and can alter call config.
- `abortSignal` (Swift: `CancellationToken`) is forwarded.
- `experimental_download` is used for image URLs in prompts (downloads happen before call).
- `instructions` are prepended as system messages (string, single message, or array).

Swift status notes:
- Tests now cover `prepareCall` overrides (toolChoice + providerOptions), `CancellationToken` forwarding, download hooks via message-based input, and `instructions` mapping.

### Object generation (`generateObject` / `streamObject`)

Tests: `ai-sdk/packages/ai/src/generate-object/*`.

Validates:

- JSON schema request formatting (including `name` / `description`),
- schema repair hook for JSON parse / validation errors,
- typed parsing (including zod transform / preprocess),
- streaming object deltas + partial-object parsing error suppression,
- promise rejection behavior (no unhandled rejections on schema mismatch).

## `provider-utils` (shared lower-level behavior)

The core themes here (relevant to AIKit’s Swift design):

- **Schema conversion & validation**: `ai-sdk/packages/provider-utils/src/schema.test.ts`
  - Zod v4 → JSON Schema draft-07 conversion with:
    - optional/required, descriptions, arrays, enums, nullable,
    - reference behavior (duplicate-by-default vs `useReferences=true`),
    - recursive schemas via `z.lazy`,
    - transform pipelines (input schema vs output validation).
  - “StandardSchema” (`~standard` / StandardJSONSchemaV1) interop and target-draft selection.

- **Robust JSON parsing/repair**: `parse-json.test.ts`, `secure-json-parse.test.ts`, plus partial parsing helpers.
  - This is the backbone behind “partial object output streaming” and “repairable JSON”.

- **Streaming + HTTP utilities**:
  - tests cover readable-stream conversions, response handlers, header normalization, retries, ID generation, and URL support checks.

## Provider packages (OpenAI / Anthropic / …)

Provider tests generally validate:

- mapping SDK-unified prompts/messages/tools into provider-specific wire formats,
- streaming event parsing into the unified `LanguageModelV3StreamPart` model (incl. text/reasoning/tool events),
- provider-specific features (e.g. metadata/citations, tool schema formatting, edge/node differences).

Example (highly relevant to “tool-input deltas”):

- `ai-sdk/packages/openai/src/chat/openai-chat-language-model.test.ts` includes scenarios producing `tool-input-start` / `tool-input-delta` / `tool-input-end` stream parts (i.e., OpenAI-style tool input streaming), which the core `streamText` pipeline then consumes and forwards.

## What this implies for AIKit (Swift)

If we aim to “match JS”, the test surface implies AIKit will eventually need:

- a **single normalized event model** for streaming (including tool-input deltas as first-class events),
- a **multi-step orchestration layer** (tool loop) shared by generate+stream,
- a **tool approval** mechanism that can short-circuit the loop and then resume,
- output parsing with:
  - JSON schema emission (draft-07-ish),
  - repairable/partial JSON parsing semantics,
  - clear typed errors (e.g. “NoObjectGenerated” equivalents),
- explicit semantics for provider-executed tools vs locally executed tools.

## TDD scaffolding plan for Swift AIKit

Goal: set up a Swift-first TDD harness that mirrors the **structure**, **scenario naming**, and **seams** of the AI SDK test suite (`ai-sdk/packages/ai` + `ai-sdk/packages/provider-utils`), while trimming server-only concerns (Node response piping).

### 1) Mirror the test taxonomy (1:1 file + scenario mapping)

Create a test tree that matches the AI SDK layout (minus server adapters):

- `Tests/AIKitCoreTests/GenerateText/GenerateTextTests.swift`
- `Tests/AIKitCoreTests/GenerateText/StreamTextTests.swift`
- `Tests/AIKitCoreTests/GenerateText/OutputSpecTests.swift`
- `Tests/AIKitCoreTests/GenerateText/ParseToolCallTests.swift`
- `Tests/AIKitCoreTests/GenerateText/RunToolsTransformationTests.swift`
- `Tests/AIKitCoreTests/GenerateText/CollectToolApprovalsTests.swift`
- `Tests/AIKitCoreTests/GenerateText/PruneMessagesTests.swift`
- `Tests/AIKitCoreTests/Agent/ToolLoopAgentTests.swift`

Each test method name should preserve the “scenario headings” from JS (so we can diff parity by grep-able strings).

### 2) Add an internal `AIKitTestKit` target (Swift equivalent of `provider-utils/test`)

Add a non-product SwiftPM target under `Sources/AIKitTestKit/` used only by test targets. It should provide:

- Deterministic utilities:
  - `TestClock` (`now()` injection)
  - `TestIDGenerator` (deterministic IDs)
- Async utilities:
  - `collect(_:)` for `AsyncSequence` / `AsyncThrowingSequence`
  - `EventRecorder` for ordered capture
- Snapshot helper (for parity with `toMatchSnapshot()`):
  - `assertSnapshot(value: Encodable, ...)` that writes stable JSON (sorted keys)
  - gated by env var `AIKIT_SNAPSHOT_RECORD=1` (no writes by default)

### 3) Build parity-first seams before orchestration

Like the JS suite, keep these as unit seams with dedicated tests (before we pile everything into `generateText/streamText` integration tests):

- Output parsing + response format (`OutputSpec` parity with `output.test.ts`)
- Tool-call parsing + repair (`parseToolCall` parity)
- Tool approvals extraction (`collectToolApprovals` parity)
- Message pruning (`pruneMessages` parity)
- Streaming tool execution/approval forwarding (`runToolsTransformation` parity)

### 4) Mock model scaffolding (closure-driven)

Create `MockLanguageModel` in `AIKitTestKit` that mirrors JS testing style:

- `doGenerate(options) async -> ModelGenerateResponse`
- `doStream(options) -> AsyncThrowingStream<ModelStreamPart>`
- Helpers to create deterministic streams from arrays (JS `convertArrayToReadableStream` analogue)

### 5) Port order (minimize risk; maximize confidence)

Suggested incremental TDD order:

1. `OutputSpecTests` (responseFormat parity first; parsing/repair later)
2. `ParseToolCallTests`
3. `CollectToolApprovalsTests` + `PruneMessagesTests`
4. `RunToolsTransformationTests` (ordering, delayed results, `onInputAvailable`, provider approval requests)
5. `GenerateTextTests` (1-step → tool loop → stopWhen/prepareStep → approvals → provider-executed tools)
6. `StreamTextTests` (fullStream/textStream → abort/errors → output parsing during streaming)
7. `ToolLoopAgentTests` (wrapper-only forwarding)

### 6) Client-only scope trimming

Skip (or postpone) server-only response piping tests:

- `pipeUIMessageStreamToResponse`, Node response-like objects, server `Response` creation helpers.

Keep the underlying **event models** and **transformation logic** they exercise (those are still critical for iOS/macOS clients consuming streams).

## Next steps order (authoritative)

This is the **required** implementation/test order moving forward. Do not reorder without explicit instruction.

1) `parseToolCall` + `ParseToolCallTests`
2) `collectToolApprovals` + `CollectToolApprovalsTests`
3) `pruneMessages` + `PruneMessagesTests`
4) `runToolsTransformation` + `RunToolsTransformationTests`
5) `generateText` + `GenerateTextTests`
6) `streamText` + `StreamTextTests`
7) `ToolLoopAgent` + `ToolLoopAgentTests` (wrapper-only forwarding)
8) `generateObject` / `streamObject` parity (post-core)

## AIKit parity tracker (JS → Swift cross‑reference)

This is the living checklist to keep parity work organized across context compaction sessions.
Each row links the **AI SDK test area** to the **Swift API surface** we need to implement/test.

Legend:
- **Swift status**: ✅ implemented, 🟡 partial, ☐ pending
- **Tests**: ✅ parity tests exist, 🟡 partial, ☐ pending

### Output parsing & response formats

- JS: `ai-sdk/packages/ai/src/generate-text/output.test.ts`
- Swift API: `Sources/AIKitCore/Output/OutputSpec.swift`
- Swift tests: `Tests/AIKitCoreTests/GenerateText/OutputSpecTests.swift`
- Status: ✅ implementation, ✅ tests

### Tool call parsing & repair

- JS: `ai-sdk/packages/ai/src/generate-text/parse-tool-call.test.ts`
- Swift API: `Sources/AIKitCore/Tools/*` (planned: `parseToolCall`, `ToolCallRepair`)
- Swift tests: `Tests/AIKitCoreTests/GenerateText/ParseToolCallTests.swift`
- Status: ✅ implementation, ✅ tests

### Tool approvals collection

- JS: `ai-sdk/packages/ai/src/generate-text/collect-tool-approvals.test.ts`
- Swift API: `Sources/AIKitCore/Tools/CollectToolApprovals.swift`
- Swift tests: `Tests/AIKitCoreTests/GenerateText/CollectToolApprovalsTests.swift`
- Status: ✅ implementation, ✅ tests

### Prune messages (reasoning/tool parts)

- JS: `ai-sdk/packages/ai/src/generate-text/prune-messages.test.ts`
- Swift API: `Sources/AIKitCore/ControlFlow/PruneMessages.swift`
- Swift tests: `Tests/AIKitCoreTests/GenerateText/PruneMessagesTests.swift`
- Status: ✅ implementation, ✅ tests

### Run tools transformation (stream-time tool execution)

- JS: `ai-sdk/packages/ai/src/generate-text/run-tools-transformation.test.ts`
- Swift API: `Sources/AIKitCore/Streaming/RunToolsTransformation.swift`
- Swift tests: `Tests/AIKitCoreTests/GenerateText/RunToolsTransformationTests.swift`
- Status: ✅ implementation, ✅ tests

### GenerateText (multi-step tool loop)

- JS: `ai-sdk/packages/ai/src/generate-text/generate-text.test.ts`
- Swift API: `Sources/AIKitCore/Generation/GenerateText.swift`
- Swift tests: `Tests/AIKitCoreTests/GenerateText/GenerateTextTests.swift`
- Status: 🟡 implementation (partial), 🟡 tests (partial coverage)

#### GenerateText missing coverage (priority order)

Priority is based on core correctness + tool-loop parity first, then callbacks/telemetry, then edge cases.

Completed:
- Tool execution errors + invalid calls in-loop
- Tool callbacks
- Provider-executed tools + deferred results
- Programmatic tool calling (multi-step fixture-style)
- options.messages behavior
- stopWhen advanced cases
- prepareStep advanced cases
- Callbacks + result surface (HIGH VALUE)
- Output integration cases

Remaining:
1) telemetry hooks (deprioritized; only if we keep telemetry in Swift)

### StreamText (streaming + multi-step tool loop)

- JS: `ai-sdk/packages/ai/src/generate-text/stream-text.test.ts`
- Swift API: `Sources/AIKitCore/Streaming/StreamText.swift`
- Swift tests: `Tests/AIKitCoreTests/GenerateText/StreamTextTests.swift`
- Status: ✅ implementation, ✅ tests

### ToolLoopAgent wrapper

- JS: `ai-sdk/packages/ai/src/agent/tool-loop-agent.test.ts`
- Swift API: `Sources/AIKitCore/Agent/ToolLoopAgent.swift`
- Swift tests: `Tests/AIKitCoreTests/Agent/ToolLoopAgentTests.swift`
- Status: ✅ implementation, ✅ tests

### GenerateObject / StreamObject (future parity)

- JS: `ai-sdk/packages/ai/src/generate-object/*`
- Swift API: (planned) object-generation wrappers around Output/Object parsing
- Swift tests: (planned) `Tests/AIKitCoreTests/GenerateObject/*`
- Status: ☐ implementation, ☐ tests

### Provider utilities (JSON schema, parsing, retry, stream helpers)

- JS: `ai-sdk/packages/provider-utils/src/*`
- Swift API: `Sources/AIKitProviders/JSON/*`, `Sources/AIKitProviders/Streaming/*`
- Swift tests: `Tests/AIKitProvidersTests/*` (only minimal currently)
- Status: 🟡 implementation (partial), ☐ tests (beyond JSONValue roundtrip)

### Provider-specific streaming (OpenAI tool-input deltas, etc.)

- JS: `ai-sdk/packages/openai/src/*` (stream parts: `tool-input-start/delta/end`)
- Swift API: `Sources/AIKitProviders/Streaming/*` + provider adapters (planned)
- Swift tests: (planned) provider adapter tests
- Status: ☐ implementation, ☐ tests
