# AIKit v2 — Apple-like Public API Proposal (Façades)

Date: December 27, 2025

This is an **API-shape proposal** only. The parity engine remains the current v2 core:

- `generateText` / `streamText` (`Sources/AIKitCore/Generation/GenerateText.swift`, `Sources/AIKitCore/Streaming/StreamText.swift`)
- `ToolLoopAgent` (`Sources/AIKitCore/Agent/ToolLoopAgent.swift`)
- `ChatSession` (`Sources/AIKitCore/ChatSession/*`)

The goal is to make the *primary* call sites feel like Apple frameworks: **configure once, call many**; small per-call overrides; minimal “plumbing types” visible to app code.

---

## Why this doc exists

We have parity scaffolding on iOS, but the public call sites aren’t “Apple-like” yet.

Also, an older version of this repo (commit `7cca10c` / `HEAD~3` as of `7b98bac`) had a nicer *shape*:
- `AIClient` as the obvious entry point
- fluent model configuration
- streaming results that acted like a collector
- `@UseChat` for SwiftUI

That implementation was not good, but the **ergonomics were**. We want those ergonomics back, **built on** the v2 parity engine.

---

## Design principles

- **Remote chat is first-class**: callers should be able to pass a **URL** (like the AI SDK’s “api path”) and never see `requestStream`/`reconnectToStream`.
- **Advanced hooks stay possible**: transports and stream injection should exist, but only as opt-in escape hatches.
- **No semantic drift**: façades must compile down to current v2 semantics (tools, approvals, step boundaries, partial output streaming).

---

## Current state vs proposed state (at a glance)

### Text generation

**Current (v2):**

```swift
let result = try await generateText(
  model: model,
  prompt: "Write a haiku about Swift concurrency.",
  output: Output.text()
)
```

**Proposed:**

```swift
let ai = AIClient(model: model) // holds defaults
let result = try await ai.generate("Write a haiku about Swift concurrency.")
```

### Remote chat (primary use case)

**Current (v2):**

```swift
let transport = AIUIChatEndpointTransport(
  url: URL(string: "https://example.com/api/chat")!,
  httpTransport: URLSessionHTTPTransport()
)

let session = ChatSession(.init(
  transport: transport,
  // Note: `system` is not part of the remote request shape; configure it server-side.
))

await session.send(.init(
  role: .user,
  parts: [.text(.init(id: UUID().uuidString, text: "Hello!", state: .done))]
))
```

**Proposed:**

```swift
let chat = ChatStore(remote: URL(string: "https://example.com/api/chat")!)
chat.sendMessage("Hello!") // `system` configured server-side
```

---

## Proposed façade #1: `AIClient` (configure-once wrapper for generate/stream/agent)

### Why

Today, `generateText`/`streamText` overloads are correct but “parameter-heavy” once you start using tools, retries, headers, etc.

`AIClient` returns the old “one entry point” feel while staying a thin adapter over:
- `GenerateTextOptions`
- `StreamTextOptions`
- `ToolLoopAgent`

### Proposed surface (sketch)

```swift
public struct AIClient: Sendable {
  public var model: any LanguageModel
  public var defaults: Defaults

  public init(model: any LanguageModel, defaults: Defaults = .init())

  public struct Defaults: Sendable {
    public var instructions: SystemPrompt?
    public var tools: ToolRegistry?
    public var toolChoice: ToolChoice
    public var activeTools: [String]?

    /// Sugar over `stopWhen: [Stop.stepCountIs(n)]`.
    public var maxSteps: Int

    public var settings: CallSettings
    public var headers: [String: String]?
    public var providerOptions: ProviderOptions?
    public var maxRetries: Int
    public var cancellationToken: CancellationToken?
    public var download: DownloadFunction?

    public init()
  }
}
```

### Examples: current vs proposed

#### 1) Multi-step tools (maxSteps sugar)

**Current (v2):**

```swift
var tools = ToolRegistry()
// tools.register(...)

let result = try await generateText(
  model: model,
  prompt: "Call the tool, then explain the result.",
  tools: tools,
  stopWhen: [Stop.stepCountIs(5)],
  output: Output.text()
)
```

**Proposed:**

```swift
var tools = ToolRegistry()
// tools.register(...)

var ai = AIClient(model: model)
ai.defaults.tools = tools
ai.defaults.maxSteps = 5

let result = try await ai.generate("Call the tool, then explain the result.")
```

#### 2) Streaming (collector stays)

**Current (v2):**

```swift
let stream = streamText(
  model: model,
  prompt: "Stream a short poem.",
  output: Output.text()
)

for try await delta in stream.textStream {
  print(delta, terminator: "")
}

let finalText = try await stream.text
```

**Proposed:**

```swift
let ai = AIClient(model: model)
let stream = ai.stream("Stream a short poem.")

for try await delta in stream.textStream {
  print(delta, terminator: "")
}

let finalText = try await stream.text
```

---

## Proposed façade #2: `ChatStore` (useChat-shaped wrapper for ChatSession)

### Problem

`ChatSession` is powerful, but it reads like an integration surface for *two* systems:

1) local, on-device chat loop (`model` provided), and  
2) remote, server-driven UI message stream (`transport`/`requestStream`/`reconnectToStream`).

Most consumers want the AI SDK’s experience: “I pass an API path/URL and use the chat state”.

### A subtle semantic gap (server chooses streamText vs agent)

In the AI SDK, `useChat` runs on the client, but **the server** decides how the assistant response is produced:

- the route can call `streamText(...)`, or
- it can call `agent.stream(...)` (`ToolLoopAgent`) and return that stream,

and the client doesn’t care.

When we run chat *locally* (no server), the same separation of responsibilities still matters: **the caller** should decide whether the session is powered by:

1) “plain” `streamText` orchestration (model + tools + instructions), or
2) a configured reusable agent (`ToolLoopAgent`) whose `prepareCall/prepareStep/stopWhen` behavior is part of the app’s design.

So `ChatStore` should not “magically pick” between them based on a `model` alone. We should make the choice explicit at initialization time, while keeping the API useChat-simple.

### Proposal: make the 90% path explicit

Provide a `ChatStore` with:

- init overloads that accept **URL** (remote-first) or **model** (local)
- published state: `messages`, `input`, `status`, `errorDescription`
- small command surface: `sendMessage`, `stop`, `regenerate`
- tool helpers: `addToolOutput`, `addToolApprovalResponse`

Under the hood it uses:
- `ChatSession` (actor) for semantics
- an internal task that listens to `ChatSession.updates()` and publishes fields (so callers don’t have to)

### Proposed surface (sketch)

```swift
@MainActor
public final class ChatStore: ObservableObject {
  private let session: ChatSession
  private var updatesTask: Task<Void, Never>?

  @Published public var messages: [ChatMessage] = []
  @Published public var input: String = ""
  @Published public var status: ChatSessionStatus = .ready
  @Published public var errorDescription: String?

  public var isLoading: Bool { status == .submitted || status == .streaming }

  /// Mirrors the AI SDK `useChat({ headers, body, metadata })` concept.
  /// Applied to requests unless overridden per-call.
  public var defaultRequestOptions: ChatRequestOptions

  /// Local execution strategy (the “server decision”, but in-process).
  public struct LocalExecutor: Sendable {
    public var stream: @Sendable (
      _ messages: [ModelMessage],
      _ headers: [String: String]?
    ) -> StreamTextResult<Output.Text>

    /// Uses `streamText(...)` directly.
    public static func streamText(
      model: any LanguageModel,
      system: SystemPrompt?,
      tools: ToolRegistry?,
      toolChoice: ToolChoice,
      activeTools: [String]?,
      stopWhen: [StopCondition] = [Stop.stepCountIs(1)]
    ) -> Self

    /// Uses a preconfigured agent (e.g. `ToolLoopAgent`) to stream.
    public static func agent<A: Agent>(
      _ agent: A
    ) -> Self where A.Output == Output.Text
  }

  /// Remote-first initializer: the common case.
  ///
  /// Note: `system` is intentionally not part of the client API in remote mode.
  /// In AI SDK usage, the system prompt lives server-side (in the route/handler).
  public init(
    remote url: URL,
    requestOptions: ChatRequestOptions = .init(),
    sendAutomaticallyWhen: (@Sendable ([ChatMessage]) async -> Bool)? = { messages in
      ChatAutoSubmitPredicates
        .lastAssistantMessageIsCompleteWithToolCallsOrApprovalResponses(messages: messages)
    }
  )

  /// Local initializer: on-device model orchestration.
  ///
  /// This is the “plain streamText” equivalent: you provide the inputs needed for streamText.
  public init(
    model: any LanguageModel,
    system: SystemPrompt? = nil,
    tools: ToolRegistry? = nil,
    toolChoice: ToolChoice = .auto,
    activeTools: [String]? = nil,
    stopWhen: [StopCondition] = [Stop.stepCountIs(1)],
    sendAutomaticallyWhen: (@Sendable ([ChatMessage]) async -> Bool)? = { messages in
      ChatAutoSubmitPredicates
        .lastAssistantMessageIsCompleteWithToolCallsOrApprovalResponses(messages: messages)
    }
  )

  /// Local initializer: use a configured agent to power chat.
  public init<A: Agent>(
    agent: A,
    sendAutomaticallyWhen: (@Sendable ([ChatMessage]) async -> Bool)? = { messages in
      ChatAutoSubmitPredicates
        .lastAssistantMessageIsCompleteWithToolCallsOrApprovalResponses(messages: messages)
    }
  ) where A.Output == Output.Text

  /// Local initializer: advanced injection point for local execution.
  public init(
    executor: LocalExecutor,
    sendAutomaticallyWhen: (@Sendable ([ChatMessage]) async -> Bool)? = { messages in
      ChatAutoSubmitPredicates
        .lastAssistantMessageIsCompleteWithToolCallsOrApprovalResponses(messages: messages)
    }
  )

  /// Escape hatch: custom transports (tests, alternate protocols).
  public init(
    transport: some ChatTransport,
    requestOptions: ChatRequestOptions = .init(),
    sendAutomaticallyWhen: (@Sendable ([ChatMessage]) async -> Bool)? = { messages in
      ChatAutoSubmitPredicates
        .lastAssistantMessageIsCompleteWithToolCallsOrApprovalResponses(messages: messages)
    }
  )

  public func sendMessage(_ text: String? = nil, options: ChatRequestOptions? = nil)
  public func regenerate(messageID: String? = nil)
  public func stop()

  public func addToolOutput(to tool: ChatToolPart, output: JSONValue)
  public func addToolOutput(toolName: String, toolCallID: String, output: JSONValue)
  public func addToolApprovalResponse(approvalID: String, approved: Bool, reason: String? = nil)

  /// Optional: for remote-only transports that support reconnect.
  public func resume() // no-op if unsupported
}
```

Note: the intent is for `ChatStore` to be the single, useChat-shaped surface most apps use (so you don’t stack wrappers).
`ChatSessionObservable` is deleted to keep the public UI surface minimal and make “what hosts should use” obvious.

### Examples: current vs proposed

#### 1) Remote chat “hello world”

**Current (v2):**

```swift
let transport = AIUIChatEndpointTransport(
  url: URL(string: "https://example.com/api/chat")!,
  httpTransport: URLSessionHTTPTransport()
)

let session = ChatSession(.init(
  transport: transport,
  // Note: `system` is not part of the remote request shape; configure it server-side.
))

await session.send(.init(
  role: .user,
  parts: [.text(.init(id: UUID().uuidString, text: "Hello!", state: .done))]
))
```

**Proposed:**

```swift
let chat = ChatStore(remote: URL(string: "https://example.com/api/chat")!)
chat.sendMessage("Hello!") // `system` configured server-side
```

#### 1b) Remote chat request options (headers/body/metadata like `useChat`)

In the AI SDK, `useChat` can attach headers/body/metadata to requests via its transport/options surface.
In AIKit v2, this already exists as `ChatRequestOptions` (mirrors AI SDK request options).

**Current (v2):**

```swift
let transport = AIUIChatEndpointTransport(
  url: URL(string: "https://example.com/api/chat")!,
  httpTransport: URLSessionHTTPTransport(),
  headers: { ["Authorization": "Bearer …"] },
  body: { .object(["appVersion": .string("1.2.3")]) }
)

let session = ChatSession(.init(transport: transport))
await session.send(.init(
  role: .user,
  parts: [.text(.init(id: UUID().uuidString, text: "Hello!", state: .done))]
), options: .init(metadata: .object(["traceID": .string("abc")])) )
```

**Proposed:**

```swift
let chat = ChatStore(
  remote: URL(string: "https://example.com/api/chat")!,
  requestOptions: .init(
    headers: ["Authorization": "Bearer …"],
    body: .object(["appVersion": .string("1.2.3")])
  )
)

chat.sendMessage("Hello!", options: .init(metadata: .object(["traceID": .string("abc")])) )
```

Note: if you want “system prompt” behavior in remote mode, treat it as **server configuration**.
If your app truly needs to vary it per-request, pass an app-specific field in `body` and have the server apply it.

#### 2) Remote chat SwiftUI view (useChat-style)

**Current (v2):**

```swift
let transport = AIUIChatEndpointTransport(
  url: URL(string: "https://example.com/api/chat")!,
  httpTransport: URLSessionHTTPTransport()
)
let session = ChatSession(.init(transport: transport))

Task {
  let updates = await session.updates()
  for await snapshot in updates {
    print(snapshot.status, snapshot.messages.count)
  }
}
```

**Proposed:**

```swift
struct ChatView: View {
  @StateObject var chat = ChatStore(remote: URL(string: "https://example.com/api/chat")!)

  var body: some View {
    VStack {
      List(chat.messages, id: \.id) { message in
        ForEach(Array(message.parts.enumerated()), id: \.offset) { _, part in
          switch part {
          case .text(let t): Text(t.text)
          case .tool(let tool): ToolPartView(tool: tool, chat: chat)
          default: EmptyView()
          }
        }
      }

      HStack {
        TextField("Message", text: $chat.input)
        if chat.isLoading {
          Button("Stop") { chat.stop() }
        } else {
          Button("Send") { chat.sendMessage() }
        }
      }
      .padding()
    }
  }
}
```

#### 3) Local chat (on-device model execution)

This is the “AIKit runs the loop locally” mode, where a local `system` prompt is appropriate.

**Current (v2):**

```swift
var tools = ToolRegistry()
// tools.register(...)

let session = ChatSession(.init(
  model: model,
  tools: tools,
  system: .instructions("You are helpful.")
))

await session.send(.init(
  role: .user,
  parts: [.text(.init(id: UUID().uuidString, text: "Hello!", state: .done))]
))
```

**Proposed:**

```swift
var tools = ToolRegistry()
// tools.register(...)

@StateObject var chat = ChatStore(
  model: model,
  system: .instructions("You are helpful."),
  tools: tools
)

chat.sendMessage("Hello!")
```

#### 3b) Local chat (agent-powered)

This mirrors the AI SDK server-side choice: instead of “ChatStore decides how to run”, you pass the thing that runs.

```swift
let agent = ToolLoopAgent<Void, Output.Text>(
  model: model,
  instructions: .instructions("You are helpful."),
  tools: tools,
  stopWhen: [Stop.stepCountIs(20)],
  output: Output.text()
)

@StateObject var chat = ChatStore(agent: agent)
chat.sendMessage("Hello!")
```

Interpretation:
- The *agent* owns the loop policy (`stopWhen`, `prepareCall`, `prepareStep`, etc).
- `ChatStore` is “UI + transcript + orchestration glue”, like `useChat`.

#### 4) Tool outputs (client-side tool execution)

**Current (v2):**

```swift
// When you see a tool part that is ready for output:
await session.addToolOutput(
  tool: ToolID<JSONValue, JSONValue>(tool.toolName),
  toolCallID: tool.toolCallID,
  output: .string("example-output")
)
```

**Proposed:**

```swift
chat.addToolOutput(to: tool, output: .string("example-output"))
```

With `sendAutomaticallyWhen` defaulting to
`lastAssistantMessageIsCompleteWithToolCallsOrApprovalResponses`, the loop continues automatically (matching the feel of AI SDK `useChat`).

#### 5) Tool approvals

**Current (v2):**

```swift
guard case let .approvalRequested(approvalID) = tool.state else { return }
await session.addToolApprovalResponse(approvalID: approvalID, approved: true)
```

**Proposed:**

```swift
guard case let .approvalRequested(approvalID) = tool.state else { return }
chat.addToolApprovalResponse(approvalID: approvalID, approved: true)
```

#### 6) Resume/reconnect (optional)

**Reality check:** on iOS, streams can drop; reconnect may matter. But in the AI SDK it’s not the “default” mental model.

**Current (v2):**

```swift
// Only works if the transport provides reconnect support.
await session.resumeStream()
```

**Proposed:**

```swift
chat.resume() // no-op if unsupported; surfaces error state if attempted and not supported
```

The key change: **resume stays available but does not contaminate the default initializer or normal usage path**.

---

## What stays “advanced” (escape hatches)

We should still support these for tests and special integrations, but we should not lead with them:

- `ChatStore.init(transport: ...)`
- `ChatSessionInit(requestStream:/reconnectToStream:)`
- manual `ChatRequestOptions` plumbing

These are analogous to `URLProtocol` / custom `URLSessionDelegate` in Apple networking: critical for some apps, but not the 90% path.

---

## Migration plan (what to build vs what to tweak)

This is not a rollout schedule; it’s a concrete “work inventory” so we’re clear what changes the repo needs.

### Build on top (no semantic changes)

These are pure façades that delegate to existing v2 types/entrypoints:

- **Add `AIClient` façade (implemented)**
  - New type in `Sources/AIKitCore` that stores defaults and calls existing `generateText(.init(...))` / `streamText(.init(...))`.
  - Re-export via `AIKit` target for convenience.
- **Add `ChatStore` façade (implemented)**
  - New SwiftUI/Combine-friendly wrapper over `ChatSession` (internally listens to `updates()` and publishes state).
  - Provide init overloads:
    - `init(remote url: URL, requestOptions: ChatRequestOptions = ...)`
    - `init(model: any LanguageModel, system: ..., tools: ..., settings: ...)` (local-only; remote system remains server-owned)
    - `init<CALL_OPTIONS>(agent: ToolLoopAgent<CALL_OPTIONS, Output.Text>)` (local-only; agent owns loop policy)
    - `init(transport: some ChatTransport, requestOptions: ...)` (escape hatch)
  - Provide useChat-shaped methods:
    - `sendMessage(_:options:)`, `stop()`, `regenerate(messageID:)`
    - `addToolOutput(...)`, `addToolApprovalResponse(...)`, optional `resume()`

- **Delete `ChatSessionObservable` (done)**
  - Removed `Sources/AIKit/ChatSessionObservable.swift` to keep the public UI surface minimal and make “what hosts should use” obvious.
- **Add “sugar” helpers (optional)**
  - Convenience builders for `ToolRegistry` construction (pure additive).
  - Optional `StreamTextResult: AsyncSequence` forwarding to `fullStream` (pure additive).

### Tweak existing (small, mostly additive, clarify responsibility boundaries)

These changes improve ergonomics and reduce confusion without removing power:

- **Remote `system` responsibility**
  - Keep `ChatSessionInit.system` for *local execution*.
  - Ensure “remote-first” convenience initializers (`ChatStore(remote:)`) do not expose `system` (server-owned).
  - Docs should emphasize: remote system prompt lives server-side; vary it via request `body` if needed.
- **Provide a URL-first remote initializer (optional but recommended)**
  - Add `ChatSessionInit(remoteURL:..., requestOptions:...)` or `ChatSessionInit.remote(url:...)` convenience that internally constructs `AIUIChatEndpointTransport`.
  - This keeps `ChatSession` usable without exposing `ChatTransport` in the common case, even if apps don’t adopt `ChatStore`.
- **Make local “runner choice” explicit**
  - Keep the current local behavior (ChatSession uses `streamText` internally).
  - Add an agent-powered path in the façade layer (`ChatStore(agent:)`) to mirror the AI SDK “server chooses agent vs streamText” separation.
  - If we ever want agent-powered execution inside `ChatSession` itself, do it by adding an explicit `localExecutor`/`agent` parameter—not by inferring from `model`.
- **Resume/reconnect semantics**
  - Keep `ChatSession.resumeStream()` as an advanced capability for transports that support it.
  - In `ChatStore`, surface it as `resume()` (optional, safe default/no-op or clear error state when unsupported) so it doesn’t pollute the primary “send” story.

### Docs + examples (important to avoid confusion)

- Update `content/docs/03-aikit-core/09-chat-session.mdx` to show two separate “tracks”:
  - **Remote (recommended)**: URL-only initialization + `ChatRequestOptions`.
  - **Local**: model-based initialization (and optionally an agent-powered example).
- Add a `content/docs/.../chat-store.mdx` page (or upgrade `ChatSession` docs to introduce the façade) so app developers see the useChat-shaped API first.
- Keep parity-level docs (`generateText` / `streamText` / `ToolLoopAgent`) intact; the façades should link “down” to them.

### Tests (what should stay stable)

- All existing parity tests for `generateText` / `streamText` / tool loop semantics should remain unchanged (façades delegate).
- Add a small set of façade-level tests:
  - `AIClient` forwards defaults → correct `GenerateTextOptions` / `StreamTextOptions`.
  - `ChatStore(remote:)` uses `AIUIChatEndpointTransport` and honors `ChatRequestOptions`.
  - `ChatStore(agent:)` uses the agent stream path (no `streamText`-specific assumptions).

---

## Mapping to AI SDK concepts (sanity check)

- AI SDK `generateText({ model, prompt, tools, stopWhen, output })`
  - v2: `generateText(model:prompt:tools:stopWhen:output:)`
  - proposed: `AIClient(model:).generate(...)` (defaults hold tools + maxSteps)

- AI SDK `streamText({ ... }) → { textStream, fullStream }`
  - v2: `streamText(...) → StreamTextResult` already provides `textStream` and `fullStream`
  - proposed: `AIClient(model:).stream(...)` returns the same `StreamTextResult`

- AI SDK `useChat({ transport: new DefaultChatTransport({ api }) })`
  - v2: `ChatSession(.init(transport: AIUIChatEndpointTransport(url: ...)))`
  - proposed: `ChatStore(remote: ...)` (transport becomes internal)

---

## Appendix: evidence references

- AI SDK usage examples: `ai-sdk/content/docs/07-reference/01-ai-sdk-core/*`
- Current v2 usage examples: `content/docs/00-introduction/02-quickstart.mdx`, `content/docs/03-aikit-core/09-chat-session.mdx`
- Old API references (to extract ergonomics, not semantics):
  - commit `f311a34` (`HEAD~2`): `Sources/AIKit/ChatSessionObservable.swift` (very minimal ObservableObject wrapper)
  - commit `7cca10c` (`HEAD~3`): `Sources/AIKit/Chat/UseChat.swift` + `AIChat` (useChat-shaped surface)
