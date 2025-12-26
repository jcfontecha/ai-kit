# AIKit `useChat` parity: API sketch + translation guide (source of truth)

This document is the **canonical specification** for implementing an AI SDK `useChat` equivalent in **AIKit** (iOS/macOS client). It is meant to be used by multiple agents translating behavior from the vendored JS AI SDK (`./ai-sdk`) into Swift.

It answers:

- What AI SDK `useChat` does (semantics, not React mechanics)
- What the AIKit API should look like (Swift-first, but parity-driven)
- Exactly how each AI SDK feature maps to AIKit “because X and Y”

## Scope

This is **only** about AI SDK UI `useChat` / `Chat` / `AbstractChat` behavior.

Out of scope (already owned by AIKit Core translation):

- `streamText` engine behavior (steps/tool loop/output parsing) beyond what `useChat` needs
- provider implementations
- schema authoring/macros

## Principles (do not violate)

1. **Alternative 1**: `ChatSession` sits *above* `streamText` / `ToolLoopAgent` (same layering as AI SDK “UI vs Core”).
2. **Parity first**: naming can be Swiftier, but semantics must match the AI SDK.
3. **Client-only reality**: some AI SDK features depend on a server transport and cannot be implemented purely via `LanguageModel`.
   - When AI SDK uses an explicit transport abstraction (e.g. stream reconnection), AIKit supports parity by allowing the app to inject the equivalent transport behavior.

---

## 1) AI SDK reference model (what we translate)

### Key source files in the vendored AI SDK

- Hook wrapper: `ai-sdk/packages/react/src/use-chat.ts`
- React state container: `ai-sdk/packages/react/src/chat.react.ts`
- Core orchestrator: `ai-sdk/packages/ai/src/ui/chat.ts` (`AbstractChat`)
- Stream → UI state: `ai-sdk/packages/ai/src/ui/process-ui-message-stream.ts`
- UI → model messages: `ai-sdk/packages/ai/src/ui/convert-to-model-messages.ts`
- Auto-resubmit helpers:
  - `ai-sdk/packages/ai/src/ui/last-assistant-message-is-complete-with-tool-calls.ts`
  - `ai-sdk/packages/ai/src/ui/last-assistant-message-is-complete-with-approval-responses.ts`

### The important architectural fact

In the AI SDK, `useChat` does **not** implement the multi-step tool loop itself.

Instead:

- `useChat` maintains a **UI message list** and streams a single assistant response from a server endpoint.
- If the streamed assistant response contains tool calls that cannot be completed server-side, the stream finishes and the UI later calls:
  - `addToolOutput` and/or `addToolApprovalResponse`
- Then `useChat` **resubmits the updated messages** (manually or via `sendAutomaticallyWhen`) to continue.

This “resubmit to continue” is the crucial semantic to preserve.

---

## 2) AIKit target model (what we are building)

### What we already have (AIKit today)

- Core streaming + tool orchestration: `Sources/AIKitCore/Streaming/StreamText.swift`
- Tool execution transform that yields tool events: `Sources/AIKitCore/Streaming/RunToolsTransformation.swift`
- Tool definitions (schema/execute/approval hooks): `Sources/AIKitCore/Tools/Tools.swift`
- Provider-facing messages: `Sources/AIKitProviders/Model/ModelMessage.swift`

### What we add (new)

We add a **UI-agnostic session container** named `ChatSession` in `AIKitCore`.

`ChatSession` is AIKit’s equivalent to AI SDK’s `AbstractChat` (not the React hook wrapper).

---

## 3) Proposed AIKit API sketch (Swift)

This is an API sketch (types + method signatures + responsibilities). It is not implementation code.

### 3.1 `ChatSessionStatus`

Mirror AI SDK status values:

```swift
public enum ChatSessionStatus: Sendable, Equatable {
  /// Messages submitted; waiting for first streaming chunk.
  case submitted
  /// Currently receiving streaming chunks.
  case streaming
  /// Idle and ready to send/regenerate.
  case ready
  /// Last request ended in error.
  case error
}
```

Translation: AI SDK `ChatStatus` in `ai-sdk/packages/ai/src/ui/chat.ts`.

### 3.2 UI-facing message model (`ChatMessage`)

AI SDK uses `UIMessage` + typed `parts` with streaming state. AIKit needs the same concept.

```swift
public struct ChatMessage: Sendable, Equatable, Identifiable {
  public var id: String
  public var role: MessageRole
  public var parts: [ChatMessagePart]

  // Optional: message-level metadata (future parity)
  public var metadata: JSONValue?
}
```

#### `ChatMessagePart`

The point is: parts must be **incrementally mutable** to reflect streaming updates and tool states.

```swift
public enum ChatMessagePart: Sendable, Equatable {
  case stepStart

  case text(ChatTextPart)
  case reasoning(ChatReasoningPart)
  case file(ChatFilePart)

  case tool(ChatToolPart)

  // Optional future parity: “data parts” / generative UI payloads
  // case data(ChatDataPart)
}
```

#### Streaming text + reasoning parts

```swift
public struct ChatTextPart: Sendable, Equatable {
  public enum State: Sendable, Equatable { case streaming, done }
  public var id: String            // stable across deltas
  public var text: String
  public var state: State
  public var providerMetadata: ProviderMetadata?
}

public struct ChatReasoningPart: Sendable, Equatable {
  public enum State: Sendable, Equatable { case streaming, done }
  public var id: String
  public var text: String
  public var state: State
  public var providerMetadata: ProviderMetadata?
}
```

#### Tool parts (static + dynamic tools, approvals, denied, etc.)

This mirrors AI SDK `ToolUIPart` / `DynamicToolUIPart` states.

```swift
public struct ChatToolPart: Sendable, Equatable {
  public enum State: Sendable, Equatable {
    case inputStreaming
    case inputAvailable

    case approvalRequested(approvalID: String)
    case approvalResponded(approvalID: String, approved: Bool, reason: String?)

    case outputDenied(reason: String?)
    case outputAvailable(preliminary: Bool)
    case outputError(errorText: String)
  }

  public var toolCallID: String
  public var toolName: String            // for dynamic tools this is a runtime string
  public var title: String?

  public var providerExecuted: Bool
  public var dynamic: Bool

  /// Parsed/partial input as JSON as it streams; `nil` if unknown.
  public var input: JSONValue?
  /// Raw input when parsing failed (matches AI SDK rawInput behavior).
  public var rawInput: JSONValue?

  /// Present when output available.
  public var output: JSONValue?

  /// Provider metadata for the tool call/result (AI SDK has callProviderMetadata).
  public var callProviderMetadata: ProviderMetadata?

  public var state: State
}
```

### 3.3 `ChatSession` (the core container)

`ChatSession` should be an `actor` (or `@MainActor final class`) to serialize state changes (AI SDK uses `SerialJobExecutor`).

```swift
public struct ChatSessionInit: Sendable {
  public var id: String?

  public var model: any LanguageModel
  public var tools: ToolRegistry?
  public var toolChoice: ToolChoice
  public var activeTools: [String]?

  public var system: SystemPrompt?
  public var settings: CallSettings
  public var headers: [String: String]?
  public var providerOptions: ProviderOptions?

  /// Equivalent to AI SDK `onToolCall` (invoked when a non-provider-executed tool call becomes input-available).
  /// If used, prefer calling `addToolOutput` without awaiting it (deadlock-avoidance parity with AI SDK docs).
  public var onToolCall: (@Sendable (_ toolCall: ChatToolPart) async -> Void)?

  /// Equivalent to AI SDK `sendAutomaticallyWhen`.
  public var sendAutomaticallyWhen: (@Sendable (_ messages: [ChatMessage]) async -> Bool)?

  /// Optional callbacks for UI integration.
  public var onError: (@Sendable (_ error: Error) async -> Void)?
  public var onFinish: (@Sendable (_ event: ChatSessionFinishEvent) async -> Void)?

  /// Inject custom ID generation for tests/determinism.
  public var generateID: (@Sendable () -> String)?
}

public struct ChatSessionFinishEvent: Sendable {
  public var message: ChatMessage
  public var messages: [ChatMessage]
  public var isCancelled: Bool
  public var isError: Bool
  public var finishReason: FinishReason?
}

public actor ChatSession {
  public nonisolated let id: String

  public private(set) var status: ChatSessionStatus
  public private(set) var error: Error?
  public private(set) var messages: [ChatMessage]

  public init(_ init: ChatSessionInit)

  // MARK: - message submission (AI SDK: sendMessage)
  public func send(_ message: ChatDraftMessage?, options: ChatRequestOptions?) async

  /// Submit using current `messages` state (AI SDK: sendMessage() with no args).
  public func submit(options: ChatRequestOptions?) async

  // MARK: - regeneration (AI SDK: regenerate)
  public func regenerate(messageID: String?, options: ChatRequestOptions?) async

  // MARK: - local edits (AI SDK: setMessages)
  public func setMessages(_ update: @Sendable ([ChatMessage]) -> [ChatMessage])

  // MARK: - tool injection (AI SDK: addToolOutput/addToolApprovalResponse)
  public func addToolOutput<I: Codable & Sendable, O: Codable & Sendable>(
    tool: ToolID<I, O>,
    toolCallID: String,
    output: O
  ) async

  public func addToolOutputError<I: Codable & Sendable, O: Codable & Sendable>(
    tool: ToolID<I, O>,
    toolCallID: String,
    errorText: String
  ) async

  public func addToolApprovalResponse(
    approvalID: String,
    approved: Bool,
    reason: String?
  ) async

  // MARK: - cancellation + error handling
  public func stop() async
  public func clearError()
}
```

#### `ChatDraftMessage` and `ChatRequestOptions`

AI SDK `sendMessage` supports “append new user message” and “replace existing user message by id”.

We model that explicitly:

```swift
public struct ChatDraftMessage: Sendable {
  public var role: MessageRole                 // mainly `.user`
  public var parts: [ChatMessagePart]          // usually `.text`/`.file`
  public var replaceMessageID: String?         // equivalent to AI SDK `messageId`
  public var metadata: JSONValue?
}

public struct ChatRequestOptions: Sendable {
  public var headers: [String: String]?
  public var body: JSONValue?                  // optional parity; may be ignored in v0
  public var metadata: JSONValue?              // optional parity; may be ignored in v0
}
```

### 3.4 Conversion: `ChatMessage[]` → `[ModelMessage]` (must mirror AI SDK)

AI SDK does *not* send UI messages directly to the model. It converts them via `convertToModelMessages`.

AIKit must do the same conversion inside `ChatSession` before calling `streamText`.

Proposed helper signature:

```swift
public struct ConvertToModelMessagesOptions: Sendable {
  public var tools: ToolRegistry?
  public var ignoreIncompleteToolCalls: Bool
}

public func convertToModelMessages(
  _ messages: [ChatMessage],
  options: ConvertToModelMessagesOptions
) async throws -> [ModelMessage]
```

Semantic requirements are in section 4.6.

---

## 4) Translation guide: AI SDK → AIKit (feature-by-feature)

This section is intentionally exhaustive. If something is not listed, it’s not part of `useChat` parity.

### 4.1 `useChat` vs `ChatSession`

AI SDK:

- `useChat` (React hook) creates a `Chat` instance that subclasses `AbstractChat`.
- `AbstractChat` owns the core behavior (messages, status, request lifecycle, tool output injection).

AIKit:

- We do **not** implement a SwiftUI hook analogue in AIKitCore.
- We implement `ChatSession` as the equivalent of `AbstractChat`.

Because:

- React hooks are not relevant on iOS/macOS.
- The behavior we want is exactly the `AbstractChat` state machine.

### 4.2 Status lifecycle (`submitted` → `streaming` → `ready` / `error`)

AI SDK:

- `makeRequest` sets `submitted`
- on first write it sets `streaming`
- on completion: `ready`
- on error: `error`
- abort resets to `ready`

AIKit:

- `ChatSession.send/submit/regenerate` sets `submitted`
- on first streamed `TextStreamPart` that causes a message write: set `streaming`
- on finish: `ready`
- on error: `error`
- on stop/cancellation: `ready` (preserve partial tokens already streamed)

Because:

- UI needs the same behavioral affordances (disable input, show spinners, etc.)
- This matches AIKit’s existing streaming model that can yield partial text before an abort.

### 4.2.1 Observation / UI updates (React vs Swift)

AI SDK:

- `AbstractChat` does not “emit updates”. It mutates an injected `ChatState` (`pushMessage`, `replaceMessage`, status changes).
- In React, the `ChatState` implementation is backed by React state, so every mutation triggers a re-render.

AIKit:

- `ChatSession` provides a framework-agnostic observation mechanism:
  - `ChatSession.updates(...) -> AsyncStream<ChatSessionSnapshot>`
  - Each mutation (message append/replace, status/error change, every streamed part application) yields a new snapshot.
- A SwiftUI app can either consume the `AsyncStream` directly in a `Task`, or use the optional `ChatSessionObservable` adapter.

Because:

- This preserves the AI SDK intent (“imperative state mutations drive UI updates”) while using Swift’s native concurrency primitives instead of React re-rendering.

### 4.3 `sendMessage` behavior (append vs replace)

AI SDK:

- `sendMessage(message)` appends a new user message (auto-generated id) then requests.
- `sendMessage({..., messageId})` replaces a specific user message, truncating later messages first.

AIKit:

- `ChatSession.send(ChatDraftMessage(... replaceMessageID: nil))` appends.
- If `replaceMessageID` is set:
  - find the message
  - require it is `.user`
  - truncate `messages` after it
  - replace it
  - submit

Because:

- This is required for “edit and regenerate” UX.
- It’s an exact translation of `AbstractChat.sendMessage` logic.

### 4.4 `submit()` (send with no message)

AI SDK:

- `sendMessage()` with no args triggers a request using the current messages.

AIKit:

- `ChatSession.submit()` triggers a request using current `messages`.

Because:

- Needed for “continue” flows where UI edits state and resubmits.

### 4.5 Regeneration

AI SDK:

- `regenerate(messageId?)` truncates conversation to before a targeted assistant message (or last message), then makes request.

AIKit:

- `ChatSession.regenerate(messageID:)` performs the same truncation behavior, then submits.

Because:

- Regeneration semantics are part of the `useChat` contract (not `streamText`).

### 4.6 Converting UI messages to model messages (critical parity)

AI SDK reference: `ai-sdk/packages/ai/src/ui/convert-to-model-messages.ts`.

AIKit translation must preserve these behaviors:

1. System messages:
   - concatenate text parts into a single system string
   - merge provider metadata into `providerOptions` (AI SDK treats it as request options)

2. User messages:
   - convert text/file parts into model message content parts
   - optional conversion of data parts (AIKit: out of scope for v0)

3. Assistant messages:
   - **split into blocks** separated by `.stepStart`
   - each block becomes one assistant model message
   - within a block:
     - text/reasoning/file parts map directly
     - tool parts map to:
       - `tool-call` entries (when not `inputStreaming`)
       - `tool-approval-request` entries when approval exists
       - for **provider-executed tools** with outputs already in assistant content, include the tool result **in assistant content** (AI SDK does this) and **do not** duplicate it into tool-role messages

4. Tool-role messages:
   - after each assistant block, if there are tool parts with results (or approval responses), emit a **tool role** message containing:
     - `tool-approval-response` entries for responded approvals
     - `tool-result` entries for non-provider-executed tool outputs, with:
       - `outputDenied` represented as an error-text output (AI SDK emits “Tool execution denied.” if no reason)

5. Option `ignoreIncompleteToolCalls`:
   - if enabled, drop tool parts with state `inputStreaming` or `inputAvailable` before conversion.

Because:

- This conversion is what makes “UI tool invocations” actually usable by `streamText` and providers.
- Without it, the “pause → UI → addToolOutput → resubmit” flow cannot work.

### 4.7 Tool calls + UI fulfilment (`addToolOutput`)

AI SDK:

- tool calls arrive via the stream and are stored as tool parts in the assistant message.
- UI later calls `addToolOutput({ tool, toolCallId, output })` to update that tool part.
- optionally `sendAutomaticallyWhen` triggers a resubmission.

AIKit:

- tool calls arrive via `TextStreamPart` and are converted into `ChatToolPart` with `.inputAvailable` state.
- UI calls `ChatSession.addToolOutput(...)` to update the matching `ChatToolPart` to `.outputAvailable`.
- then:
  - either user calls `submit()` manually
  - or `sendAutomaticallyWhen` triggers auto-submit (see 4.9)

Because:

- This exactly matches the AI SDK UX model: tool results are injected into the current assistant message and then included in the next request via conversion.

Important nuance:

- In AIKit, tools can also be executed automatically via `ToolRegistry` + `streamText` tool execution transform.
- `ChatSession` must still support manual fulfilment for UI tools by allowing tools with no `execute` or tools gated behind approvals.

### 4.7.1 `onToolCall` (automatic client-side tools)

AI SDK:

- `onToolCall` is invoked when a tool call is received from the stream (specifically at `tool-input-available`) and `providerExecuted` is false.
- It is currently **awaited** (blocking) in `processUIMessageStream`.
- Typical usage: automatically run a client-side tool and call `addToolOutput` (the docs recommend not awaiting `addToolOutput`).

AIKit:

- `ChatSessionInit.onToolCall` is invoked when the session observes a `ChatToolPart` transition to `inputAvailable` for a non-provider-executed tool.
- It should be **awaited** (blocking) for parity, but the implementation should document the same deadlock avoidance pattern:
  - `onToolCall` may call `addToolOutput(...)` (without awaiting it) to inject output and let auto-resubmit continue.

Because:

- This is the AI SDK’s sanctioned pattern for “automatic client-side tools” without requiring UI interaction.

Practical guidance for AIKit:

- Prefer defining auto-executed tools in `ToolRegistry` with `execute`, since AIKit is client-only and can execute locally.
- Use `onToolCall` when tool handling needs to live in the UI layer (e.g. interacting with app state) but is still “automatic”.

### 4.7.2 Tool input streaming (`tool-input-start/delta/end`)

AI SDK:

- `processUIMessageStream` stores partial tool call JSON text in `partialToolCalls[toolCallId].text`
- on each `tool-input-delta`, it appends `inputTextDelta`, calls `parsePartialJson(text)`, and writes the (possibly undefined) `input` back into the tool part while it is still `input-streaming`.

AIKit:

- `ChatMessageStreamingReducer.State.partialToolInputs[toolCallId]` accumulates the raw JSON string
- on each `.toolInputDelta`, AIKit attempts to parse/repair partial JSON into `JSONValue` via `OutputParsing.parsePartialJSONValue(_:)` and writes that into `ChatToolPart.input` while the tool part is still `.inputStreaming`.
- `.toolInputEnd` clears the accumulated raw text (the authoritative tool call will arrive as `.toolCall` / “input-available”).

Because:

- UI parity requires showing tool arguments progressively (OpenAI-style tool input deltas).
- AIKit already has partial JSON repair for streamed structured output; reuse it for tool input streaming.

### 4.8 Approvals (`addToolApprovalResponse`)

AI SDK:

- stream can contain `tool-approval-request`; UI updates via `addToolApprovalResponse({ id, approved, reason })`
- then either resubmits manually or via `sendAutomaticallyWhen`

AIKit:

- stream yields `TextStreamPart.toolApprovalRequest`
- ChatSession records `ChatToolPart.state = .approvalRequested(approvalID: ...)`
- UI calls `addToolApprovalResponse(...)` which updates tool part state to `.approvalResponded(...)`
- continuation uses the same resubmit mechanism as tool outputs.

Because:

- Approval is explicitly modeled as part of the assistant message and is part of the “resubmit to continue” loop.

### 4.9 Auto-resubmit (`sendAutomaticallyWhen`)

AI SDK:

- `sendAutomaticallyWhen` is invoked when:
  1) a stream finishes, and
  2) a tool output is added, and
  3) an approval response is added
- if it returns true, `useChat` triggers another request (without blocking/awaiting to avoid deadlocks)

AIKit:

- `ChatSessionInit.sendAutomaticallyWhen` is invoked at the same points:
  - after request finishes and status becomes `ready`
  - after `addToolOutput` / `addToolApprovalResponse`
- if it returns true and the session is not currently `submitted/streaming`, `ChatSession` calls `submit()` in a detached task (or internal task queue).

Because:

- This pattern is how AI SDK implements multi-iteration conversations when tools are client-fulfilled.
- Deadlock avoidance is important for UI callbacks (same rationale).

#### Helpers (AI SDK parity)

AI SDK ships helpers:

- `lastAssistantMessageIsCompleteWithToolCalls`
- `lastAssistantMessageIsCompleteWithApprovalResponses`

AIKit should ship equivalents operating on `ChatMessage` (not `ModelMessage`), with identical semantics:

- consider only the last assistant message
- consider only the last step (after last `.stepStart`)
- ignore `providerExecuted` tool invocations
- “complete with tool calls” means: at least one tool invocation exists and all have output available or error
- “complete with approvals” means: at least one approval responded exists and all are either output available/error or approval responded

### 4.10 Stop / cancellation (`stop()`)

AI SDK:

- `stop()` aborts the active fetch stream via `AbortController`
- keeps already streamed tokens/messages
- sets status back to `ready`

AIKit:

- `stop()` cancels the active streaming `Task` (or triggers `CancellationToken` in `streamText`).
- does not discard already written parts.
- status becomes `ready`.

Because:

- “Stop generation” UX must preserve partial results.
- AIKit does not have fetch abort; it has structured concurrency cancellation.

### 4.11 Error handling (`error`, `clearError`, `onError`, `onFinish`)

AI SDK:

- errors set status to `error` and store `error`
- `clearError` resets to `ready`
- `onFinish` is called in `finally` with flags (abort/disconnect/error + finishReason)

AIKit:

- store `error: Error?` and `status = .error`
- `clearError()` sets `error = nil` and `status = .ready` (only when currently `.error`)
- `onFinish` callback receives `ChatSessionFinishEvent` including:
  - `isCancelled` (AIKit’s analogue to abort)
  - `isError`
  - `finishReason` if known

Because:

- UI parity requires stable error lifecycles.
- AIKit cannot reliably distinguish “disconnect” vs other errors without a transport layer; so we do not promise `isDisconnect` parity.

### 4.12 Stream resumption (`resumeStream`)

AI SDK:

- `resumeStream()` reconnects via transport to `/api/chat/{chatId}/stream`

AIKit:

- `ChatSession.resumeStream()` is supported only when the app injects a reconnection implementation:
  - `ChatSessionInit.reconnectToStream: (chatID, options) -> AsyncThrowingStream<TextStreamPart, Error>?`
- If `reconnectToStream` returns `nil`, AIKit treats it as “no active stream found” and returns to `ready` without mutating messages.

Because:

- AI SDK already models reconnection via a transport abstraction; AIKit mirrors this by allowing injection rather than hardcoding an HTTP layer into core.
- `LanguageModel` does not provide resumption semantics; reconnection is necessarily app/provider specific.

### 4.13 Throttling — intentional non-parity (v0)

AI SDK:

- React-specific throttling via `experimental_throttle` for UI updates

AIKit:

- Not part of core parity; can be implemented by SwiftUI layer (coalescing updates) if needed.

Because:

- It’s a UI framework performance concern, not chat semantics.

---

## 5) Implementation checkpoints (what other agents should build)

This list is ordered so that each step is testable and reduces ambiguity.

1. Define UI message types (`ChatMessage`, parts, tool states) and deterministic ID generation hooks.
2. Implement conversion `ChatMessage[] -> [ModelMessage]` with tests translated from:
   - `ai-sdk/packages/ai/src/ui/convert-to-model-messages.test.ts`
3. Implement `ChatSession` request lifecycle (status transitions, stop, clearError) with tests translated from:
   - `ai-sdk/packages/ai/src/ui/chat.test.ts` (only the `AbstractChat` tests, not React UI tests)
4. Implement `addToolOutput` and `addToolApprovalResponse` and auto-resubmit helpers, with tests translated from:
   - `ai-sdk/packages/ai/src/ui/last-assistant-message-is-complete-with-*.test.ts`
