# AIKit `useChat` parity: test translation checklist

This document enumerates the exact **vendored AI SDK test suites** that define `useChat` semantics and maps them to the **AIKit test files** we should create.

This is a companion to the canonical spec: `AIKIT_USECHAT_TRANSLATION.md:1`.

## Goals

- Make it unambiguous what “done” means for AIKit `ChatSession` parity.
- Give other agents a single checklist of “translate these tests → implement until green”.

## AI SDK sources of truth (tests)

### 1) ChatSession core behavior (AI SDK `AbstractChat`)

AI SDK test file:

- `ai-sdk/packages/ai/src/ui/chat.test.ts`

Translate the entire suite under `describe('Chat', ...)`, including these groups:

- `describe('send a simple message', ...)`
- `describe('send handle a disconnected response stream', ...)`
- `describe('send handle a stop and an aborted response stream', ...)`
- `describe('sendAutomaticallyWhen', ...)`
- `describe('clearError', ...)`
- `describe('addToolApprovalResponse', ...)`
- `describe('addToolResult', ...)` (AI SDK deprecated name; maps to `addToolOutput`)

AIKit notes:

- Any “send messages to API” assertions become “sent request to the model”, verified via a **visible `LanguageModel` test double** that records the last `ModelRequest`.
- “disconnect” cannot be precisely detected in AIKit (no fetch transport); model it as “stream throws an error” and assert `.error` status + callback.
- “abort” maps to Swift concurrency cancellation (or AIKit `CancellationToken`) and should behave like AI SDK abort: keep partial tokens, return to `.ready`.

### 2) UI message → model message conversion (critical)

AI SDK test file:

- `ai-sdk/packages/ai/src/ui/convert-to-model-messages.test.ts`

Translate the full suite except the final group:

- ✅ `describe('system message', ...)`
- ✅ `describe('user message', ...)`
- ✅ `describe('assistant message', ...)`
- ✅ `describe('multiple messages', ...)`
- ✅ `describe('error handling', ...)`
- ✅ `describe('when ignoring incomplete tool calls', ...)`
- ✅ `describe('when converting dynamic tool invocations', ...)`
- ✅ `describe('when converting provider-executed dynamic tool invocations', ...)`
- ✅ `describe('when converting tool approval request responses', ...)`
- ⏭️ `describe('data part conversion', ...)` (out of scope for v0 unless we introduce “data parts” into `ChatMessagePart`)

AIKit notes:

- This suite defines how `ChatMessage` blocks map to `ModelMessage` blocks, including step boundaries and the “tool role message” emission rules.
- Port these tests first: everything else depends on the conversion being correct.

### 3) Auto-resubmit helpers (tool/approval completeness predicates)

AI SDK test file:

- `ai-sdk/packages/ai/src/ui/last-assistant-message-is-complete-with-tool-calls.test.ts`

Translate entire suite.

AIKit notes:

- AI SDK also has `lastAssistantMessageIsCompleteWithApprovalResponses` but does not ship a dedicated test file; its behavior is exercised in `chat.test.ts` (in the approvals section). AIKit should add an explicit test suite for the approval helper anyway.

### 4) Stream → UI message assembly (reference-driven subset)

AI SDK test file:

- `ai-sdk/packages/ai/src/ui/process-ui-message-stream.test.ts`

We do **not** translate the entire file (it’s very large and is centered on `UIMessageChunk` and transports).

Instead, translate only the following describe blocks as behavioral reference for AIKit’s “stream parts → `ChatMessage` updates” state machine:

- `describe('text', ...)` (text-start/delta/end)
- `describe('reasoning', ...)`
- `describe('tool call streaming', ...)` (tool-input-start/delta/available + partial JSON parsing behavior)
- `describe('tool input error', ...)`
- `describe('preliminary tool results', ...)`
- `describe('tool title support', ...)`
- `describe('tool approval requests (static tool)', ...)`
- `describe('tool approval requests (dynamic tool)', ...)`
- `describe('tool execution denial (static tool)', ...)`
- `describe('tool execution denial (dynamic tool)', ...)`

AIKit notes:

- AIKit consumes `TextStreamPart` from `streamText`, not `UIMessageChunk`. The point is to match the *resulting tool/text part state transitions*.
- Use snapshot-style assertions for the resulting `ChatMessage.parts` arrays after each streamed part.

## Proposed AIKit test layout

Create a new folder:

- `Tests/AIKitCoreTests/ChatSession/`

Suggested files (mirroring AI SDK groupings):

1. `Tests/AIKitCoreTests/ChatSession/ChatSessionTests.swift`
   - Mirrors `ai-sdk/.../ui/chat.test.ts`

2. `Tests/AIKitCoreTests/ChatSession/ConvertToModelMessagesTests.swift`
   - Mirrors `ai-sdk/.../ui/convert-to-model-messages.test.ts` (except data parts)

3. `Tests/AIKitCoreTests/ChatSession/ChatAutoSubmitPredicatesTests.swift`
   - Mirrors tool call completeness + approval completeness helpers

4. `Tests/AIKitCoreTests/ChatSession/ChatMessageStreamingReducerTests.swift`
   - Behavioral tests for “apply TextStreamPart → mutate last assistant `ChatMessage`”
   - Mirrors the *selected* describes from `process-ui-message-stream.test.ts`

## Test doubles required (shared)

To keep tests deterministic and fast, define minimal test doubles in `Tests/AIKitTestKit` or local to the test files:

- `TestLanguageModel: LanguageModel`:
  - records received `ModelRequest`s (for “send to API” parity)
  - returns a controllable `AsyncThrowingStream<ModelStreamPart, Error>` for streaming scenarios

- Deterministic ID generator:
  - `ChatSessionInit.generateID` should be injected in tests (AI SDK uses `mockId()` heavily).

## Checklist (translation order)

1. ☐ Implement `ChatMessage` + part types from `AIKIT_USECHAT_TRANSLATION.md:1`
2. ☐ Translate `convert-to-model-messages.test.ts` → `ConvertToModelMessagesTests.swift`
3. ☐ Implement `convertToModelMessages(...)` until green
4. ☐ Translate `last-assistant-message-is-complete-with-tool-calls.test.ts` → `ChatAutoSubmitPredicatesTests.swift`
5. ☐ Implement AIKit helper predicates until green
6. ☐ Translate `chat.test.ts` → `ChatSessionTests.swift`
7. ☐ Implement `ChatSession` lifecycle (send/submit/regenerate/stop/clearError) until green
8. ☐ Translate selected `process-ui-message-stream.test.ts` blocks → `ChatMessageStreamingReducerTests.swift`
9. ☐ Implement streaming reducer logic (TextStreamPart → ChatMessage updates) until green

