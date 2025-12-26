# Plan: Use AIKit `ChatSession` with a Node AI SDK `streamText` streaming endpoint

> Consolidated plan (Dec 25, 2025). This document replaces the following drafts (now archived):
> - `AIKIT_CHATSESSION_AISDK_STREAMTEXT_PLAN.md`
> - `AIKIT_CHATSESSION_AI_SDK_STREAMTEXT_PLAN.md`
> - `AIKIT_CHATSESSION_AI_SDK_STREAMING_ENDPOINT_PLAN.md`
> - `AIKIT_CHATSESSION_AI_SDK_STREAMTEXT_ENDPOINT_PLAN.md`
> - `AIKIT_CHATSESSION_NODE_STREAMTEXT_PLAN.md`
> - `AIKIT_NODE_STREAMTEXT_CHATSESSION_PLAN.md`

## Goal
Enable a native iOS app (AIKit) to drive chat UI state via `ChatSession`, while the actual model execution happens **server-side** in a Node app using the **real Vercel AI SDK** (`streamText` and/or `ToolLoopAgent`).

Concretely:
- iOS uses `ChatSession` APIs (`send`, `regenerate`, `addToolOutput`, `addToolApprovalResponse`, `sendAutomaticallyWhen`-style auto-submit).
- Node exposes an HTTP streaming endpoint that returns an AI SDK **UI Message Stream** (SSE, protocol v1).
- AIKit adds a small “transport” layer so `ChatSession` can consume that stream instead of calling a local `LanguageModel`.

## Non-goals (initially)
- Replacing AIKitCore’s `streamText` implementation.
- Implementing AI SDK server adapters (`toUIMessageStreamResponse`) in Swift.
- Full parity with every AI SDK UI stream part (`data-*`, files/sources) on day one.

## Current state (what we already have)
- AIKit `ChatSession` is an `actor` that owns:
  - transcript (`[ChatMessage]`),
  - lifecycle (`ChatSessionStatus`: submitted/streaming/ready/error),
  - tool injection (`addToolOutput`, `addToolApprovalResponse`),
  - optional `reconnectToStream` hook.
- `ChatSession` can call AIKitCore `streamText` locally in `ChatSession.runRequest(...)`; local `TextStreamPart` events are adapted into `AIUIMessageStreamPart` and applied to UI state via `ChatMessageStreamingReducer`.
- `ChatSession` consumes **AI SDK UI message stream protocol** parts and applies them to UI state via `ChatMessageStreamingReducer`.
  - Local model streaming (`streamText`) is adapted into UI message stream parts to reuse the same reducer logic.

Key files:
- `Sources/AIKitCore/ChatSession/ChatSession.swift`
- `Sources/AIKitCore/ChatSession/ChatMessageStreamingReducer.swift`
- `Sources/AIKitCore/Streaming/StreamText.swift` (`TextStreamPart`)

## Reference: AI SDK server-side pieces we’re targeting
- Server executes `streamText({ model, messages, tools, stopWhen, ... })`.
- Server returns an SSE response using `result.toUIMessageStreamResponse()`.
- Protocol details:
  - Header: `x-vercel-ai-ui-message-stream: v1`
  - Content-Type: `text/event-stream`
  - Each SSE `data:` line contains JSON like `{ "type": "text-delta", ... }`
  - Terminated by `data: [DONE]`.

Docs worth keeping open:
- AI SDK Core `streamText` reference: https://vercel.com/docs/reference/ai-sdk-core/stream-text
- AI SDK UI Stream Protocol: https://vercel.com/docs/ai-sdk-ui/stream-protocol
- AI SDK UI Chatbot Tool Usage: https://vercel.com/docs/ai-sdk-ui/chatbot-tool-usage

---

## Protocol reality (what the server can stream)
The AI SDK has two relevant streaming formats:

1) **Text Stream Protocol** (`toTextStreamResponse()`)
- Plain text chunks only.
- Not sufficient for tools / approvals / multi-step parity.

2) **UI Message Data Stream Protocol (SSE)** (`toUIMessageStreamResponse()`)
- SSE (`text/event-stream`) where each event is `data: {json}` and the stream ends with `data: [DONE]`.
- Includes step boundaries, tool input streaming, tool results, and (depending on the AI SDK version/features) approval-related parts.
- Requires header: `x-vercel-ai-ui-message-stream: v1`.

This plan targets **(2)**. If we discover missing/ambiguous fields we need on iOS (e.g. usage/finish metadata), we can extend it using AI SDK’s `data-*` custom parts (see “Open Questions”).

---

## Proposed Architecture

### 1) Node: `POST /chat/stream` streams UI Message Stream (SSE)
- Request body includes:
  - conversation messages (either **AI SDK `UIMessage[]`** or **AI SDK `ModelMessage[]`**),
  - optional client-sent tool outputs / approval responses already merged into the message list,
  - optional chat/session identifiers for resuming.
- Response is the AI SDK UI Message Stream (SSE).

### 2) iOS: `ChatSession` uses a transport to:
- serialize its current transcript into request JSON,
- open a streaming HTTP request with `URLSession.bytes(for:)`,
- parse SSE events into a local event type,
- decode events into AI SDK UI message stream protocol parts (Swift enum),
- feed those parts into `ChatMessageStreamingReducer`.

### 3) Resume support (optional)
Use `ChatSessionInit.reconnectToStream` as the iOS entry point for:
- reconnecting to a still-running server stream,
- or resuming a “message stream” from server persistence.

Recommended minimal contract (matches AI SDK UI `HttpChatTransport`):
- `GET /api/chat/:id/stream`:
  - `200 OK` + UI message stream (SSE v1) **while** a stream is active for that `id`
  - `204 No Content` once there is no active stream to resume

Recommended server approach (stateful Node):
- Keep an in-memory “active stream registry” keyed by `id`.
- When `POST /api/chat` starts streaming:
  - register the active stream under `id`
  - fan out the output to:
    - the original POST caller, and
    - any future `GET /api/chat/:id/stream` reconnect callers
- When the AI SDK stream ends:
  - remove the registry entry so future reconnects return `204`

See `content/docs/06-advanced/04-node-server-chat-session.mdx` for a reference fan-out implementation.

---

## Key Design Decision: What to send from iOS → Node

### Option A (recommended): send AI SDK `UIMessage[]`
Pros:
- Matches AI SDK UI server examples.
- Server can use `convertToModelMessages(messages)` exactly as documented.

Cons:
- iOS must implement conversion from `ChatMessage` → AI SDK `UIMessage` JSON.

### Option B: send AI SDK `ModelMessage[]`
Pros:
- iOS can reuse AIKitCore `convertToModelMessages(...)` to produce model-shaped messages.
- Server can pass `messages` directly to `streamText` without conversion.

Cons:
- Requires a stable, documented JSON contract for model messages (and any tool message variants).

Plan: start with **Option A** if we want maximum alignment with AI SDK UI semantics, especially around tool parts, approvals, and persistence. If the mapping is painful, fall back to Option B.

---

## Key Design Decision: What to stream from Node → iOS

### Option A (recommended): AI SDK UI Message Stream (SSE v1)
Pros:
- Official, stable contract intended for non-JS clients.
- Includes tool-input streaming and multi-step boundaries.

Cons:
- iOS must parse SSE and decode event JSON into AIKit `AIUIMessageStreamPart`.

### Option B: a custom JSON stream mirroring AIKit `AIUIMessageStreamPart`
Pros:
- iOS can decode directly with fewer mapping rules.

Cons:
- Less alignment with AI SDK; more custom code on server.

Plan: implement **Option A**, with a small mapping layer in Swift.

---

## Work Plan

### Phase 0 — Validate the exact stream events we must support
1. Implement a tiny Node endpoint that does `streamText(...).toUIMessageStreamResponse()`.
2. Capture a real stream transcript (raw SSE lines) for these scenarios:
   - plain text response,
   - tool input streaming (`tool-input-start` + `tool-input-delta`),
   - tool execution with tool result,
   - multi-step (`start-step`/`finish-step`),
   - errors,
   - approvals (if present as explicit stream parts).
3. Produce a definitive list of stream event shapes (fields per `type`).

Deliverable: a JSON schema / table for event mapping.

### Phase 1 — Node endpoint (server-side)
1. Add `POST /chat/stream` (Express/Fastify/Next.js route) that:
   - reads `messages` from JSON body,
   - uses AI SDK `convertToModelMessages` if using UI messages,
   - calls `streamText({ model, messages, tools, stopWhen, ... })`.
2. Choose tool strategy:
   - **server-executed tools**: define tools with `execute` on server.
   - **client-executed tools**: define tools without `execute` so tool calls are streamed and the client later posts tool results.
3. Return `result.toUIMessageStreamResponse()`.

Hard requirements:
- Set `x-vercel-ai-ui-message-stream: v1`.
- Ensure proper SSE headers (`Content-Type: text/event-stream`, `Cache-Control: no-cache`).
- Ensure the route flushes output and terminates with `[DONE]`.

Optional (later):
- `POST /chat/resume` (or same route with `chatId`) to support stream resumption.

### Phase 2 — Swift: Streaming client + SSE parser
1. Add an SSE parser that converts `AsyncThrowingStream<UInt8, Error>` into events:
   - read lines,
   - group `data:` lines into one event payload,
   - ignore comments / ping events,
   - detect terminal `data: [DONE]`.
2. Decode JSON event payload into a Swift enum like:
   - A typed enum mirroring `UIMessageChunk` in the AI SDK (e.g. `AIUIMessageStreamPart`) plus small structs for tool-related chunks.
3. Feed those parts into `ChatMessageStreamingReducer` (and keep request-level status/error handling in `ChatSession`):
   - `text-*` → mutate the current assistant message text parts
   - `reasoning-*` → mutate reasoning parts
   - `tool-input-*` / `tool-output-*` → mutate tool invocation parts
   - `start-step` / `finish-step` → step boundary markers
   - `finish` → final `finishReason` (request-level)

Notes:
- AIKit’s reducer already handles tool call/result and tool input streaming.
- If AI SDK uses different naming (`tool-call`/`tool-result` vs `tool-input-available`/`tool-output-available`), support both.

Deliverable: `AsyncThrowingStream<AIUIMessageStreamPart, Error>` from a URL.

### Strictness and versioning (client-side)
- Require `x-vercel-ai-ui-message-stream: v1` (fail early with a clear error if missing).
- Ignore unknown event `type`s (or optionally preserve them for diagnostics), so newer AI SDK parts don’t break older clients.

### Phase 3 — Swift: Add a ChatSession transport hook (parity with AI SDK `ChatTransport`)
`ChatSession` currently hard-codes a local `streamText` call in `runRequest`.

Add a new injection point so `ChatSession` can stream from a remote endpoint:

1. Introduce a closure in `ChatSessionInit`, e.g.:
  - `requestStream: (chatID, messages, trigger, messageID, options, cancellationToken) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error>`
   - `trigger` mirrors AI SDK UI transport semantics (`submit-message` / `regenerate-message` / `resume-stream`).
   - `messageID` matches AI SDK `messageId` behavior (used for replace/regenerate flows).
   - `reconnectToStream` stays for resuming.
2. Update `ChatSession.runRequest` to:
   - if `requestStream` exists: call it using the *submitted snapshot* of `messages` + request options + trigger/messageId;
   - else: keep current local `streamText` behavior.

This mirrors the AI SDK UI idea:
- `useChat` uses a transport to call `/api/chat`.
- Our iOS `ChatSession` uses a transport to call `/chat/stream`.

Deliverable: iOS can opt into “remote streaming mode” without changing app code that uses `ChatSession`.

### Phase 4 — Message serialization (ChatSession → request JSON)
Implement a conversion from AIKit `ChatMessage[]` into the chosen request format:

- If sending AI SDK `UIMessage[]`:
  - Map:
    - user text parts → UI `text` parts
    - assistant text parts → UI `text` parts
    - tool parts in assistant messages → UI tool invocation parts (must include toolCallId/toolName/state/input/output)
    - tool-role messages (if present in transcript) → UI equivalents

- If sending AI SDK `ModelMessage[]`:
  - Use AIKitCore `convertToModelMessages(...)` (already exists) and then map to AI SDK’s JSON shape.

Deliverable: request body builder used by the transport.

### Phase 5 — Tools + approvals end-to-end (multi-iteration)
1. Verify the core “resubmit to continue” loop works:
   - server streams a tool call (no execute), ends step,
   - iOS UI calls `ChatSession.addToolOutput(...)`,
   - `sendAutomaticallyWhen` triggers `submit()` again,
   - server receives messages including the tool result and continues.
2. Repeat for approvals:
   - server streams an approval request,
   - iOS calls `addToolApprovalResponse(...)`,
   - auto-submit continues.

Optional parity: “default auto-submit predicates”
- Mirror AI SDK UI helpers like `lastAssistantMessageIsCompleteWithToolCalls` / approval equivalents by providing recommended `sendAutomaticallyWhen` predicates in AIKit.

Deliverable: parity with the AI SDK UI “tool usage” flow, but in native iOS.

### Phase 6 — Tests and fixtures
1. Swift unit tests for the SSE parser:
   - fragmented byte boundaries,
   - multiple `data:` lines per event,
   - `[DONE]` termination.
2. Swift tests for mapping:
   - feed recorded SSE transcripts and snapshot resulting `ChatSessionSnapshot.messages`.
3. (Optional) Node integration tests:
   - ensure headers and termination match AI SDK protocol.

---

## Minimal mapping table (starting point)
This table should be validated against captured real streams (Phase 0).

| AI SDK UI stream `type` | Example fields | AIKit `AIUIMessageStreamPart` |
|---|---|---|
| `start` | `messageId` | `.start` |
| `text-start` | `id` | `.textStart(id: ...)` |
| `text-delta` | `id`, `delta` | `.textDelta(id: ..., text: ...)` |
| `text-end` | `id` | `.textEnd(id: ...)` |
| `reasoning-start` | `id` | `.reasoningStart(id: ...)` |
| `reasoning-delta` | `id`, `delta` | `.reasoningDelta(id: ..., text: ...)` |
| `reasoning-end` | `id` | `.reasoningEnd(id: ...)` |
| `tool-input-start` | `toolCallId`, `toolName` | `.toolInputStart(id: toolCallId, toolName: toolName, ...)` |
| `tool-input-delta` | `toolCallId`, `inputTextDelta` | `.toolInputDelta(id: toolCallId, delta: inputTextDelta, ...)` |
| `tool-input-available` | `toolCallId`, `toolName`, `input` | emit `.toolCall(...)` (preferred) |
| `tool-output-available` | `toolCallId`, `output` | `.toolResult(...)` |
| `start-step` | (optional metadata) | `.startStep()` |
| `finish-step` | (optional metadata) | `.finishStep(...)` |
| `error` | `errorText` | `.error(errorText)` |
| `finish` | (maybe `usage`) | `.finish(...)` or treat as end |

---

## Acceptance criteria
- A single `ChatSession` instance can drive a full conversation against a Node endpoint.
- Transcript renders progressively and correctly reflects:
  - step boundaries
  - tool-input streaming → tool call → tool result
  - approval request → approval response → continuation
- No deadlocks when `onToolCall` triggers tool execution.
- Clear error handling on disconnect / server error.

---

## Open Questions (answer early)
1. Does AI SDK UI stream v1 include explicit `tool-approval-request`/`tool-approval-response` event types? If not, how are approvals represented in the stream?
2. Do we need stable IDs from server (`messageId`) to support resume, or can iOS ignore and use its own `ChatMessage.id`?
3. Do we want to support `data-*` custom parts for app-specific streaming payloads?
4. Should we support both:
   - server-executed tool loop (tools with `execute`), and
   - client-executed tools (no `execute`, iOS uses `addToolOutput`)?
5. Metadata requirements: do we need `usage`, `finishReason`, provider metadata on iOS?
   - If yes and the UI stream doesn’t carry enough detail, add a `data-ai-kit` (or similar) custom part in the server stream to carry that metadata.
6. Security posture: how does the iOS app authenticate to the server endpoint (bearer token, session cookie, etc.)?

---

## Milestones
- M0: Node endpoint streams `toUIMessageStreamResponse()` for plain text.
- M1: Swift SSE parser produces a typed event stream.
- M2: Swift maps UI stream events → `AIUIMessageStreamPart` and drives `ChatMessageStreamingReducer`.
- M3: `ChatSession` gains a transport hook and can run fully against the endpoint.
- M4: Client tool outputs and approvals round-trip and auto-resubmit works.
- M5: Resume/reconnect (optional) using `ChatSessionInit.reconnectToStream`.

---

## Immediate next actions
1. Server spike: implement a minimal Node endpoint returning `toUIMessageStreamResponse()` and capture raw SSE transcripts for mapping.
2. Swift decoder: implement SSE → UI stream event → `AIUIMessageStreamPart` (unit-test with fixtures).
3. Transport API: add a `ChatTransport`-style abstraction and wire it into `ChatSession.submit()` (keep local `streamText` as default).
4. End-to-end demo: iOS app renders streamed assistant text from the endpoint.
5. Tools + approvals: add one client-side tool + one approval-gated tool to validate the resubmit loop.
