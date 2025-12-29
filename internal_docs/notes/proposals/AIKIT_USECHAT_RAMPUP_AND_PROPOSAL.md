# AIKit: ai-sdk `useChat` ramp-up + proposal

Note: This file is a ramp-up snapshot. The canonical “source of truth” spec for implementing `useChat` parity in AIKit is `AIKIT_USECHAT_TRANSLATION.md:1`.

This note captures what the vendored JS **AI SDK** does for `useChat` and proposes an equivalent architecture for **AIKit** (iOS/macOS client).

## 1) ai-sdk `useChat` ramp-up (what it actually is)

In the AI SDK, **`useChat` is a UI-state wrapper around a `Chat` class**, and the real orchestration lives in `AbstractChat`.

Key files:

- React hook wrapper: `ai-sdk/packages/react/src/use-chat.ts`
- React `Chat` class (state + subscriptions): `ai-sdk/packages/react/src/chat.react.ts`
- Core chat orchestrator: `ai-sdk/packages/ai/src/ui/chat.ts` (`AbstractChat`)
- Stream → UI message parts: `ai-sdk/packages/ai/src/ui/process-ui-message-stream.ts`
- Helpers for “auto-resubmit when ready”:  
  `ai-sdk/packages/ai/src/ui/last-assistant-message-is-complete-with-tool-calls.ts`  
  `ai-sdk/packages/ai/src/ui/last-assistant-message-is-complete-with-approval-responses.ts`
- Docs on tool flows (server tools / client tools / approvals): `ai-sdk/content/docs/04-ai-sdk-ui/03-chatbot-tool-usage.mdx`

### What `AbstractChat` owns

`AbstractChat` is a client-side state machine for:

- `messages: UIMessage[]` (UI-shaped messages, not provider-shaped)
- `status: 'submitted' | 'streaming' | 'ready' | 'error'`
- `error: Error?`
- request lifecycle: `sendMessage`, `regenerate`, `resumeStream`, `stop`, `clearError`
- “injecting” user-supplied results back into the message stream:
  - `addToolOutput(...)` (aka the former `addToolResult`)
  - `addToolApprovalResponse(...)`
- optional continuation policy: `sendAutomaticallyWhen({ messages }) -> Bool`

Under the hood:

- It sends requests via a `ChatTransport` (default is HTTP to `/api/chat`).
- It consumes a **typed event stream** (`UIMessageChunk`) and updates the last assistant message incrementally.
- It serializes all state changes with a `SerialJobExecutor` to avoid race conditions.

### How tools work in `useChat`

AI SDK supports 3 tool “modes” in a `useChat` app (as documented):

1. **Server-executed tools**: the server route calls `streamText` with tools that have `execute`, and the server forwards tool results in the stream.
2. **Client-executed tools (automatic)**: the server forwards tool calls; client handles them in `onToolCall` and calls `addToolOutput(...)`.
3. **Client tools requiring UI**: the tool call is rendered in UI; later UI calls `addToolOutput(...)`.

Approvals (`needsApproval`) are a first-class flow:

- Stream can include `tool-approval-request`.
- UI calls `addToolApprovalResponse(...)`.
- You typically configure `sendAutomaticallyWhen` (or manually call `sendMessage`) to continue.

The important separation: **the “tool loop” continues by resubmitting messages**, not by having `useChat` directly run a multi-step model loop itself.

## 2) Mapping to AIKit (constraints + what’s already here)

AIKit already has:

- `streamText` + `ToolLoopAgent` in `Sources/AIKit` (core orchestration).
- Tool concepts aligned with AI SDK:
  - typed tool inputs via `ObjectSchema<T>`
  - `needsApproval`
  - tool kinds (`.client` vs `.provider(...)`)
  - tool input streaming hooks (`onInputStart/onInputDelta/onInputAvailable`)
- Streaming event model via `TextStreamPart` including tool calls, results, and approvals.

Big difference vs JS:

- AIKit is **client-only**, so there’s no natural “server boundary” separating:
  - **model streaming + tool loop engine** (AI SDK Core)
  - **chat UI state container** (AI SDK UI)

But there is still a real architectural separation worth preserving:

- **Headless generation** (services, view models, background tasks) should be able to call `streamText`/`ToolLoopAgent` without any chat/session machinery.
- **Interactive sessions** (SwiftUI/AppKit) need a state container that:
  - owns message history + status
  - reacts to streaming deltas
  - pauses/resumes on approvals and UI-fulfilled tools

## 3) Proposal: AIKit `ChatSession` (useChat analogue)

### Recommendation

Prefer **Alternative (1)**: keep `ToolLoopAgent`/`streamText` as core building blocks and implement chat as a *layer on top* (analogous to AI SDK’s `streamText` vs `useChat` split).

Rationale (based on AI SDK semantics):

- `useChat` is not “the tool loop”; it is a **message-state container** that *coordinates* tool loop continuation.
- Keeping `streamText` usable outside chat is valuable for non-chat use cases (your “viewmodel/service operations” point).
- UI-implication tools map cleanly to the AI SDK concept of “client-side tools requiring interaction”: they are surfaced as tool call parts and later fulfilled.

### What AIKit should add (API surface)

Add a UI-agnostic chat/session type in `AIKit` (SwiftUI can wrap it later):

- `ChatSession` (an `actor` or `@MainActor final class`) holding:
  - `id`, `messages`, `status`, `error`
  - `send(...)`, `regenerate(...)`, `stop()`, `clearError()`
  - `addToolOutput(...)` and `addToolApprovalResponse(...)` (same conceptual names as AI SDK)
  - `sendAutomaticallyWhen`-style policy (optional; default helpers)

Key design point: **ChatSession should be able to pause on “unresolved client tools” and approvals**, then resume when the app supplies tool output / approval responses.

Concretely, ChatSession owns two representations:

1. A UI-facing message list (with stable `id`s and incremental parts, like AI SDK `UIMessage`).
2. A provider-facing `ModelMessage` list (AIKitProviders) derived from (1) when making a model call.

### Required semantic alignment (important)

In the AI SDK, if a tool call is not executed (client-side tool with no `execute` on server), the stream finishes with `finishReason: toolCalls` and the system waits for the client to provide tool output and resubmit.

For AIKit chat parity, `streamText`/tool-loop behavior must allow this pause/resume cycle:

- If a tool call is emitted but not executed locally (e.g. tool has `execute == nil`), the current streaming run should **stop** (or otherwise surface “requires action” such that ChatSession can stop).
- After UI provides output (via `addToolOutput`), ChatSession triggers the next iteration by calling `streamText` again with the updated messages.

This matches the AI SDK’s “resubmit messages to continue” semantics, just without the server hop.

## 4) Alternatives (tradeoffs)

### Alternative 1: keep `ToolLoopAgent/streamText` outside chat (recommended)

Pros:

- Matches AI SDK layering (Core vs UI state container).
- Keeps `streamText` useful for “headless” workflows.
- Makes UI-heavy tools (approvals/navigation/presentation) naturally modelled as “pause + resume”.
- Lets you ship a lightweight `ChatSession` without forcing everyone into it.

Cons:

- You must define a UI-facing message model (AI SDK’s `UIMessage` analogue) and conversion to `ModelMessage`.
- Requires clear rules for when the engine pauses (unresolved tools, approvals, cancellations).

### Alternative 2: bundle tool loop + streaming into chat session

Pros:

- Single object owns everything; fewer public entry points.
- Might feel simpler for “just build a chat UI” apps.

Cons:

- Makes non-chat uses awkward (you end up depending on chat/session types in service layers).
- Encourages UI coupling in tool execution (tools end up awaiting UI state directly).
- Harder to test and evolve independently (tool-loop semantics vs UI state updates).

## 5) Concrete next step (if you want to proceed)

If we align on Alternative 1, the next increment could be:

1. Define AIKit’s `UIMessage` analogue and tool-part state model (mirroring AI SDK parts/state names).
2. Implement `ChatSession` around `streamText`, including pause/resume on approvals and “unresolved tool calls”.
3. Mirror a small subset of AI SDK `useChat` tests as Swift tests (status transitions, tool call + addToolOutput, approvals + addToolApprovalResponse).
