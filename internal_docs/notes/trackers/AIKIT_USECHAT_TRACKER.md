# AIKit `useChat` → `ChatSession` parity tracker (features + tests)

Last updated: 2025-12-26

Single source of truth for:
- **Feature parity** between AIKit `ChatSession` and the Vercel AI SDK UI `useChat`/`AbstractChat` behavior.
- **Test parity**: which vendored AI SDK unit tests have been translated and are passing in Swift.

Primary goal (zoomed out):
- Ship the Node AI SDK endpoint integration described in `AIKIT_CHATSESSION_AI_SDK_STREAM_ENDPOINT_PLAN.md`.

Canonical spec references:
- `AIKIT_USECHAT_TRANSLATION.md`
- `AIKIT_CHATSESSION_AI_SDK_STREAM_ENDPOINT_PLAN.md`
- `AIKIT_USECHAT_TESTS_CHECKLIST.md`

## Legend

- [x] Done
- [ ] Not started
- [~] In progress / partial
- [n/a] Not applicable (JS-only)
- [!] Blocked / unclear in AI SDK (needs validation)

---

## Status (high level)

- [x] Core `ChatSession` lifecycle parity (local `LanguageModel` mode)
- [~] Remote SSE transport parity (Node AI SDK UI message stream v1)
- [~] AI SDK-compatible `UIMessage[]` request payload contract (Swift encoder)
- [x] “Data parts” / generative UI (`data-*`) parity

---

## A) Feature parity (what exists in product code)

### A1) ChatSession core (`AbstractChat`) parity

Source of truth: `ai-sdk/packages/ai/src/ui/chat.ts` + `ai-sdk/packages/ai/src/ui/chat.test.ts`.

- [x] Status lifecycle: `.submitted → .streaming → .ready` / `.error`
- [x] `send(...)` (append) and `replaceMessageID` (replace + truncate)
- [x] `submit()` sends with current transcript
- [x] `regenerate(messageID:)` truncation behavior
- [x] `stop()` cancels and preserves partial output
- [x] `clearError()` resets `.error → .ready`
- [x] `onToolCall` for non-provider-executed tool calls
- [x] `addToolOutput(...)` + `addToolOutputError(...)`
- [x] `addToolApprovalResponse(...)` (updates both state + `approval` object)
- [x] `sendAutomaticallyWhen` resubmission points (finish/tool output/approval response)
- [x] `onFinish` parity flags (`isAbort`/`isDisconnect`/`isError` + `finishReason`)
- [x] Request options parity (`ChatRequestOptions.body` / `.metadata`)
  - [x] `ChatRequestOptions.body` merged into remote request body via `AIUIChatEndpointTransport`.
  - [x] `ChatRequestOptions.metadata` passed as requestMetadata to transport hooks (not included in request body by default).
- [x] Stream schema validation hooks (`messageMetadataSchema` / `dataPartSchemas` parity)

### A2) Stream → UI assembly parity (`process-ui-message-stream`)

Source of truth: `ai-sdk/packages/ai/src/ui/process-ui-message-stream.ts` (+ tests; see section B).

- [x] Text parts: `text-start`/`text-delta`/`text-end`
- [x] Reasoning parts: `reasoning-start`/`reasoning-delta`/`reasoning-end`
- [x] Tool input streaming (delta → partial JSON parsing into `ChatToolPart.input`)
- [x] Tool call → tool result → state transitions in `ChatMessage.parts`
- [x] Tool approval request/response representation
- [x] Tool denial / preliminary result / title edge cases
- [x] Data UI parts: `data-*` (including transient + replace-by-id updates) + `onData` callback
- [x] File/source parts: `file`, `source-url`, `source-document`
- [x] Optional schema validation: message metadata + data parts

### A3) UI messages → model messages conversion parity (`convert-to-model-messages`)

Source of truth: `ai-sdk/packages/ai/src/ui/convert-to-model-messages.ts`.

- [x] System message conversion
- [x] User message conversion (text/file/image where supported)
- [x] Assistant message conversion
- [x] Tool call/result/error/approval conversions into model-layer messages
- [x] “Data parts” conversion parity (`convertDataPart` hook)

### A4) Auto-resubmit helper predicates parity

Source of truth:
- `lastAssistantMessageIsCompleteWithToolCalls`
- `lastAssistantMessageIsCompleteWithApprovalResponses`

- [x] Tool-call completeness predicate(s) exist + tests
- [x] Approval completeness predicate(s) exist + tests

### A5) Remote transport parity (Node AI SDK endpoint → ChatSession)

Goal: allow iOS `ChatSession` to be driven by a server-side AI SDK `streamText` endpoint, matching the AI SDK “resubmit to continue” model.

- [x] `ChatSessionInit.requestStream` hook for remote streaming (no local `LanguageModel` required)
  - [x] Supports cancellation via `CancellationToken` (abortSignal parity)
- [x] SSE parsing + UI message stream event decoding (`SSEUIMessageStreamDecoder`)
- [x] Header strictness: require `x-vercel-ai-ui-message-stream: v1` (`AIUIMessageStreamClient`)
- [x] Unknown UI message stream `type` forwards as `.raw(JSONValue)` for forward compatibility (except `data-*`, which is first-class)

Missing for parity / productization:
- [x] First-class `ChatTransport` abstraction (Swift analogue + default URLSession HTTP transport)
- [~] Standardized request payload encoding:
  - [~] Swift `ChatMessage[]` → AI SDK `UIMessage[]` JSON encoder (including tool/approval parts)
  - [x] Swift decoder for AI SDK `UIMessage[]` → `ChatMessage[]` (persistence/rehydration)
- [~] Request shape parity (`trigger` + `messageId`) end-to-end contract doc + examples (server/client)
- [~] Resume stream parity (`resumeStream` + server persistence + recommended contract)
  - [x] Hook exists (`ChatSessionInit.reconnectToStream`)
  - [~] Client helper exists (GET `.../:id/stream`, 204 => nil)
  - [x] Server persistence contract documented (active stream lookup; 204 semantics; fan-out sample)
- [~] Metadata/usage parity:
  - [x] `finish` event maps to `TextStreamPart.finish` when present
  - [x] `start`/`finish`/`message-metadata` merge into `ChatMessage.metadata` (deep object merge; AI SDK `mergeObjects` semantics)
  - [ ] Decide if we need a custom `data-ai-kit` part to carry usage/finish/provider metadata when absent

---

## B) Test parity (AI SDK suite → Swift suite mapping)

Goal: for every `useChat`/`AbstractChat` feature we port into `ChatSession`, we also port the **corresponding AI SDK unit tests** (or an equivalent Swift assertion when the JS test is environment-specific).

### B1) `ai-sdk/packages/ai/src/ui/chat.test.ts` → `Tests/AIKitTests/ChatSession/ChatSessionTests.swift`

- [x] `describe('send a simple message', ...)`
- [x] `describe('send handle a disconnected response stream', ...)` (Swift: thrown stream error; no fetch-specific detection)
- [x] `describe('send handle a stop and an aborted response stream', ...)` (Swift: `CancellationToken` mirrors abortSignal)
- [x] `describe('sendAutomaticallyWhen', ...)`
- [x] `describe('clearError', ...)`
- [x] `describe('addToolApprovalResponse', ...)`
- [x] `describe('addToolResult', ...)` (AIKit: `addToolOutput`)

### B2) `ai-sdk/packages/ai/src/ui/convert-to-model-messages.test.ts` → `Tests/AIKitTests/ChatSession/ConvertToModelMessagesTests.swift`

- [x] `describe('system message', ...)`
- [x] `describe('user message', ...)`
- [x] `describe('assistant message', ...)`
- [x] `describe('multiple messages', ...)`
- [x] `describe('error handling', ...)`
- [x] `describe('when ignoring incomplete tool calls', ...)`
- [x] `describe('when converting dynamic tool invocations', ...)`
- [x] `describe('when converting provider-executed dynamic tool invocations', ...)`
- [x] `describe('when converting tool approval request responses', ...)`
- [x] `describe('data part conversion', ...)` (port: user + assistant conversion suite)

### B3) `ai-sdk/packages/ai/src/ui/last-assistant-message-is-complete-with-tool-calls.test.ts` → `Tests/AIKitTests/ChatSession/ChatAutoSubmitPredicatesTests.swift`

- [x] Entire suite translated

### B4) `ai-sdk/packages/ai/src/ui/process-ui-message-stream.test.ts` → `Tests/AIKitTests/ChatSession/ChatMessageStreamingReducerTests.swift`

Selected describes (we only port the parts that impact `ChatMessage`/tool state):
- [x] `describe('text', ...)`
- [x] `describe('reasoning', ...)`
- [x] `describe('tool call streaming', ...)` (partial JSON parsing)
- [x] `describe('tool input error', ...)`
- [x] `describe('preliminary tool results', ...)`
- [x] `describe('tool title support', ...)`
- [x] `describe('tool approval requests (static tool)', ...)`
- [x] `describe('tool approval requests (dynamic tool)', ...)`
- [x] `describe('tool execution denial (static tool)', ...)`
- [x] `describe('tool execution denial (dynamic tool)', ...)`
- [x] `describe('data ui parts', ...)` (single / transient / id replace / object replace)

### B5) `ai-sdk/packages/ai/src/ui/http-chat-transport.test.ts` → `Tests/AIKitTests/ChatSession/RemoteTransport/AIUIChatEndpointTransportTests.swift`

- [x] Body merge/request shape (transport body + per-request body)
- [x] Headers (transport headers + per-request headers; adds `User-Agent` suffix `aikit/swift`)
- [x] Reconnect semantics (GET `.../:id/stream`, 204 => nil)

---

## C) Next actions (most goal-aligned toward the endpoint plan)

1. ✅ Finish reducer test parity for the selected `process-ui-message-stream` describes (B4).
2. ✅ Finish transport request/headers/reconnect test parity for `http-chat-transport.test.ts` (B5).
3. ✅ Write/lock a concrete Node endpoint contract + examples (POST request shape + GET resume shape) per `AIKIT_CHATSESSION_AI_SDK_STREAM_ENDPOINT_PLAN.md` (`content/docs/06-advanced/04-node-server-chat-session.mdx`).
