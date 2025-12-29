# AIKit Proposal (iOS/macOS client)

This document proposes an **AIKit** Swift Package that matches the behavior of the JS AI SDK for:

- `generateText`
- `streamText` (including structured output schema definitions and partial output streaming)
- `ToolLoopAgent` (multi-step tool loop with approvals and stop conditions)

It is designed to be **Swift-forward**, **type-safe**, and suitable for **iOS/macOS client apps**.

---

## Goals

- Provide a small, composable core (`AIKit`) that is provider-agnostic.
- Preserve the JS SDK’s semantics:
  - multi-step tool loop for `generateText` and `streamText`
  - structured outputs via schemas (`Output.text/object/array/choice/json`)
  - streaming that produces both `textStream` and `fullStream`, plus `partialOutputStream`
  - tool approvals (`needsApproval`) and “tool input streaming” hooks (`onInputStart/onInputDelta/onInputAvailable`)
- Make tools and outputs strongly typed at the call site (as far as Swift allows).
- Make providers pluggable via a single canonical `LanguageModel` interface.

## Non-goals (for v0)

- Server-only helpers (HTTP response piping, edge runtime integration).
- Key management strategy (the SDK accepts API keys/tokens via provider configuration).
- Auto-generating JSON Schema for arbitrary Swift types (can be added later with macros/codegen).

---

## Package layout

Swift Package targets:

- `AIKit`
  - `generateText`, `streamText`
  - `ToolLoopAgent`
  - prompt/message types, streaming event types
  - tool registry + tool execution
  - output specs + schema abstraction
  - stop conditions + usage/metadata
- `AIKitProviders` (protocols + helpers)
  - `LanguageModel`, `HTTPTransport`, common SSE/chunk decoders
- Future: `AIKitOpenAI`, `AIKitAnthropic`, `AIKitOpenAICompatible`, …

---

## Core API (draft)

### Messages and content

```swift
public enum ModelMessage: Sendable {
  case system(SystemMessage)
  case user(UserMessage)
  case assistant(AssistantMessage)
  case tool(ToolMessage)
}

public struct SystemMessage: Sendable { public var content: String }
public struct UserMessage: Sendable { public var content: [UserPart] }
public struct AssistantMessage: Sendable { public var content: [AssistantPart] }
public struct ToolMessage: Sendable { public var content: [ToolPart] }
```

Content parts (normalized so all providers map into the same types):

```swift
public enum AssistantPart: Sendable {
  case text(String, metadata: ProviderMetadata? = nil)
  case reasoning(String, metadata: ProviderMetadata? = nil)
  case toolCall(ToolCall)                 // parsed tool call (stable)
  case toolApprovalRequest(ToolApprovalRequest)
}

public enum ToolPart: Sendable {
  case toolResult(ToolResult)
  case toolError(ToolError)
  case toolApprovalResponse(ToolApprovalResponse)
}
```

### Language model protocol (provider-agnostic)

Providers implement *only* this protocol; all tool loop + output parsing is in `AIKit`.

```swift
public protocol LanguageModel: Sendable {
  var id: String { get }
  var capabilities: ModelCapabilities { get }

  func generate(_ request: ModelRequest) async throws -> ModelResponse
  func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error>
}
```

### Schema strategy (matching `../ai-kit`)

AIKit should support **two schema authoring modes** (macro-first, plus a manual escape hatch), inspired by `../ai-kit` but updated to fit the unified `generateText/streamText` + `OutputSpec` API.

1) **Swift-first (recommended): macros that generate `SchemaProviding` + `ObjectSchema<T>`**
   - Annotate your type with `@AIModel`.
   - Optionally annotate stored properties with `@Field(...)` for descriptions/constraints.
   - The macro generates:
     - `extension T: SchemaProviding`
     - `static var schema: ObjectSchema<T>`
     - nested `struct Partial` for typed partial output streaming (“all fields optional”).

2) **Manual JSON Schema (escape hatch): `ObjectSchema<T>.manual(jsonSchema: …)`**
   - For types you can’t annotate or don’t want to add macros for, pass an explicit JSON Schema payload.
   - Still decode/validate into `T` via `Codable`.

This yields “Zod-like” ergonomics in Swift without losing JSON Schema interoperability.

#### Will this work seamlessly with the API we’re designing?

Yes, with two important adjustments (to avoid blindly copying older assumptions):

1) **Treat schemas as “provider guidance + runtime validation”, not as a separate type system.**
   - In the JS SDK, schemas serve two roles: *prompting/constraint* (JSON schema sent to provider) and *validation* (parse + validate on receipt).
   - In Swift, the clean analogue is:
     - Provider guidance: `ObjectSchema<T>.jsonSchema`
     - Validation: `Decodable` decode + optional JSON Schema validation (strict/lenient policies)
   - This integrates cleanly with `OutputSpec` (complete parsing + partial parsing) and with tool input parsing.

2) **Typed partials must be intentionally “lossy”.**
   - JS emits partial objects opportunistically (it repairs partial JSON and does not validate partials).
   - If we make `partialOutputStream` strongly typed (`T.Partial`), `T.Partial` must be designed to decode from incomplete objects (typically “all fields optional”).
   - If we offer macros, they should generate a permissive `Partial` type by construction; otherwise users can define `Partial` manually.

#### Macros (optional, not required for AIKit)

Swift macros are ergonomically great, but they can be painful in some Xcode build workflows (approval prompts, plugin trust, etc.), and that friction is especially problematic for agentic/CLI-driven workflows.

Macros live in a **separate Swift package** (`./AIKitMacros`) so the main AIKit package does not depend on SwiftSyntax. See `MACROS_FEASIBILITY.md`.

Proposal:

- `AIKit` must not require macros.
- If we ship macros at all, they live in a separate optional package so projects can opt in.
- Provide a CLI-friendly alternative for “generated schema + generated Partial”:
  - `AIKitCodegen` (an executable target) that reads annotated Swift source (or a small YAML/JSON manifest) and **generates**:
    - `static var schema` boilerplate
    - permissive `Partial` types
  - Generated files are checked into source control, so builds are “just Swift” (no compiler plugins).

Minimal core types:

```swift
public protocol SchemaProviding: Codable, Sendable {
  associatedtype Partial: Codable & Sendable
  static var schema: ObjectSchema<Self> { get }
}

public struct ObjectSchema<T: Codable & Sendable>: Sendable {
  public var jsonSchema: JSONSchema
  public var name: String?
  public var description: String?
}
```

Schema authoring examples:

```swift
import AIKit
import AIKitMacro

@AIModel
struct Person: Codable, Sendable {
  @Field("Full legal name", minLength: 1)
  let name: String

  @Field("Age in years", range: 0...150)
  let age: Int

  @Field("Optional contact email", format: "email")
  let email: String?
}

// The macro synthesizes:
// - `static var schema: ObjectSchema<Person>`
// - `struct Person.Partial`

// Escape hatch (manual JSON Schema):
let personSchema = ObjectSchema<Person>.manual(
  jsonSchema: .object(
    properties: [
      "name": .string(minLength: 1),
      "age": .integer(minimum: 0, maximum: 150),
      "email": .string(format: "email"),
    ],
    required: ["name", "age"],
    additionalProperties: false
  ),
  name: "Person",
  description: "Person profile"
)
```

### Tools (typed IDs + type-erased registry)

Swift can’t infer tool maps like TypeScript object literals, so we use typed tool IDs.

```swift
public struct ToolID<Input: Sendable, Output: Sendable>: Hashable, Sendable {
  public var name: String
  public init(_ name: String) { self.name = name }
}

public struct ToolContext: Sendable {
  public var toolCallID: String
  public var messages: [ModelMessage]      // excludes system + assistant tool-call message (matches JS semantics)
  public var cancellation: TaskCancellationToken
  public var userContext: AnySendable?     // optional user-defined context
}

public struct ToolSpec<Input: Codable & Sendable, Output: Codable & Sendable>: Sendable {
  public var title: String?
  public var description: String?
  public var inputSchema: JSONSchema
  public var needsApproval: ToolNeedsApproval<Input>?
  public var onInputStart: (@Sendable (ToolContext) async -> Void)?
  public var onInputDelta: (@Sendable (_ delta: String, _ ctx: ToolContext) async -> Void)?
  public var onInputAvailable: (@Sendable (_ input: Input, _ ctx: ToolContext) async -> Void)?

  public var execute: (@Sendable (Input, ToolContext) async throws -> ToolExecution<Output>)?
}

public enum ToolExecution<Output: Sendable>: Sendable {
  case final(Output)
  case streaming(AsyncThrowingStream<ToolProgress<Output>, Error>)
}

public enum ToolProgress<Output: Sendable>: Sendable {
  case preliminary(Output)
  case final(Output)
}
```

Registry (type-erased storage, typed registration):

```swift
public struct ToolRegistry: Sendable {
  public init()
  public mutating func register<I: Codable & Sendable, O: Codable & Sendable>(
    _ id: ToolID<I,O>,
    _ tool: ToolSpec<I,O>
  )
}

Tool schema best practice:

- If `Input` conforms to `SchemaProviding`, provide `inputSchema = Input.schema.jsonSchema`.
- Otherwise, provide `ObjectSchema<Input>.manual(jsonSchema: …)` (or direct `JSONSchema`) to keep tools fully described for providers.
```

### Output specs (structured output + partial streaming)

```swift
public protocol OutputSpec: Sendable {
  associatedtype Complete: Sendable
  associatedtype Partial: Sendable

  var responseFormat: ResponseFormat { get }
  func parseComplete(text: String, context: OutputContext) async throws -> Complete
  func parsePartial(text: String) async -> Partial?
}

public enum Output {
  public static func text() -> some OutputSpec<Complete == String, Partial == String>
  public static func json() -> some OutputSpec<Complete == JSONValue, Partial == JSONValue>
  public static func object<T: Codable & Sendable>(
    _ type: T.Type,
    schema: ObjectSchema<T>,
    name: String? = nil,
    description: String? = nil
  ) -> some OutputSpec<Complete == T, Partial == JSONValue>
  public static func typedObject<T: SchemaProviding>(
    _ type: T.Type,
    name: String? = nil,
    description: String? = nil
  ) -> some OutputSpec<Complete == T, Partial == T.Partial>
  public static func array<E: Codable & Sendable>(
    _ element: E.Type,
    elementSchema: ObjectSchema<E>,
    name: String? = nil,
    description: String? = nil
  ) -> some OutputSpec<Complete == [E], Partial == JSONValue>
  public static func choice(
    options: [String],
    name: String? = nil,
    description: String? = nil
  ) -> some OutputSpec<Complete == String, Partial == String?>
}
```

**Key behavior to match JS SDK:** for JSON-ish outputs, `streamText` should buffer text deltas and only emit a text delta (and a partial output) when `parsePartial` returns a *new* partial value.

When `Output.typedObject(T.self)` is used, `parsePartial` should decode into `T.Partial` (typically an “all fields optional” partial type) to provide typed partial streaming.

### Stop conditions

```swift
public typealias StopCondition = @Sendable (_ steps: [StepResult]) async -> Bool

public enum Stop {
  public static func stepCountIs(_ n: Int) -> StopCondition
  public static func hasToolCall(_ toolName: String) -> StopCondition
}
```

### `generateText`

```swift
public struct GenerateTextOptions<TOOLS: Sendable, OUT: OutputSpec>: Sendable {
  public var model: any LanguageModel
  public var system: String?
  public var messages: [ModelMessage]?
  public var prompt: String?

  public var tools: ToolRegistry?
  public var toolChoice: ToolChoice
  public var activeTools: [String]?

  public var stopWhen: [StopCondition]
  public var output: OUT

  public var onStepFinish: (@Sendable (StepResult) async -> Void)?
  public var onFinish: (@Sendable (GenerateTextFinish) async -> Void)?
}

public func generateText<OUT: OutputSpec>(
  _ options: GenerateTextOptions<Void, OUT>
) async throws -> GenerateTextResult<OUT>
```

`generateText` runs a loop:

1. Call model with current messages/tools/responseFormat.
2. Parse tool calls; for each tool call:
   - call `onInputAvailable`
   - if `needsApproval == true`, emit a `toolApprovalRequest` part in the assistant message and stop looping
   - else execute tools **concurrently by default** (matching JS)
3. Append tool results as a tool message.
4. Stop when finishReason != `.toolCalls` or a stop condition triggers.
5. Parse `output` only if the final finishReason is `.stop` (otherwise `result.output` throws “No output generated”).

### `streamText`

```swift
public struct StreamTextOptions<OUT: OutputSpec>: Sendable {
  public var model: any LanguageModel
  public var system: String?
  public var messages: [ModelMessage]?
  public var prompt: String?

  public var tools: ToolRegistry?
  public var toolChoice: ToolChoice
  public var activeTools: [String]?
  public var stopWhen: [StopCondition]
  public var output: OUT

  public var onChunk: (@Sendable (TextStreamPart) async -> Void)?
  public var onStepFinish: (@Sendable (StepResult) async -> Void)?
  public var onFinish: (@Sendable (StreamTextFinish) async -> Void)?
}

public func streamText<OUT: OutputSpec>(
  _ options: StreamTextOptions<OUT>
) -> StreamTextResult<OUT>
```

`StreamTextResult` exposes:

```swift
public struct StreamTextResult<OUT: OutputSpec>: Sendable {
  public var textStream: AsyncThrowingStream<String, Error>
  public var fullStream: AsyncThrowingStream<TextStreamPart, Error>
  public var partialOutputStream: AsyncThrowingStream<OUT.Partial, Error>

  public func consume() async
  public var text: String { get async throws }
  public var output: OUT.Complete { get async throws }
  public var steps: [StepResult] { get async throws }
  public var totalUsage: Usage { get async throws }
}
```

---

## `ToolLoopAgent`

Agents provide a reusable “configured” wrapper around `generateText` / `streamText`.

```swift
public struct ToolLoopAgent<OUT: OutputSpec>: Sendable {
  public var id: String?
  public var model: any LanguageModel
  public var instructions: SystemPrompt?
  public var tools: ToolRegistry

  public var toolChoice: ToolChoice
  public var stopWhen: [StopCondition]       // default: [Stop.stepCountIs(20)]
  public var output: OUT

  public var prepareCall: (@Sendable (AgentCall) async -> AgentCall)?

  public init(…)

  public func generate(prompt: String) async throws -> GenerateTextResult<OUT>
  public func stream(prompt: String) -> StreamTextResult<OUT>
}
```

Agent behavior matches JS:

- instructions are injected as system message(s)
- instructions are injected as system message(s) (string or system messages with providerOptions)
- `prepareCall` can mutate per-call options (e.g., attach metadata or providerOptions)
- default stop condition is 20 steps

---

## Provider architecture (high level; no provider specifics)

Providers should be *adaptors* that translate between:

- canonical `ModelRequest/ModelResponse/ModelStreamPart` types, and
- provider HTTP APIs and streaming formats.

### Transport (testable)

```swift
public protocol HTTPTransport: Sendable {
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
  func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, HTTPURLResponse)
}
```

Production: `URLSessionTransport`. Tests: `MockTransport`.

### Provider implementation pattern

- `RequestEncoder` turns `ModelRequest` into `URLRequest` (JSON + headers).
- `ResponseDecoder` turns response JSON into `ModelResponse`.
- `StreamDecoder` parses bytes to provider events (SSE/chunked JSON), maps to `ModelStreamPart`.
- `ErrorMapper` converts provider errors to typed `ModelError`.

Core code never sees provider-specific payloads.

### Tool input streaming support (provider variability)

Some providers can emit **tool input streaming** events (start + argument deltas + end) and some only emit a final tool call.

AIKit should support both:

- If the provider emits tool input deltas, AIKit forwards:
  - `tool-input-start`
  - `tool-input-delta`
  - `tool-input-end`
  and invokes tool hooks `onInputStart/onInputDelta`.
- If the provider does not emit tool input deltas, AIKit still forwards the parsed `tool-call` and invokes `onInputAvailable` once the final input is parsed.

Provider reality (for planning): OpenAI commonly emits tool-input deltas; Anthropic often needs an opt-in header/setting to stream tool input.

---

## Example usage

### 1) Basic `generateText`

```swift
let model: any LanguageModel = /* from a provider target */

let result = try await generateText(.init(
  model: model,
  system: .text("You are a helpful assistant."),
  prompt: "Invent a new holiday and describe its traditions.",
  tools: nil,
  toolChoice: .auto,
  activeTools: nil,
  stopWhen: [Stop.stepCountIs(1)],
  output: Output.text()
))

print(result.text)
```

### 2) Typed object output

```swift
import AIKitMacro

@AIModel
struct Sentiment: Codable, Sendable {
  @Field("positive | negative | neutral", enum: ["positive", "negative", "neutral"])
  let sentiment: String

  @Field("0...1 confidence score", range: 0...1)
  let score: Double

  @Field("Short summary of the review", minLength: 1)
  let summary: String
}

let result = try await generateText(.init(
  model: model,
  prompt: #"Analyze: "The product exceeded my expectations!""#,
  stopWhen: [Stop.stepCountIs(1)],
  output: Output.typedObject(Sentiment.self)
))

let output = try result.output
print(output.summary)
```

### 3) Tools + `ToolLoopAgent`

```swift
import AIKitMacro

@AIModel
struct WeatherInput: Codable, Sendable {
  @Field("City name, e.g. \"Paris\"", minLength: 1)
  let city: String
}
struct WeatherOutput: Codable, Sendable { let celsius: Double; let condition: String }

let weatherTool = ToolSpec<WeatherInput, WeatherOutput>(
  title: "Weather",
  description: "Get current weather by city name",
  inputSchema: WeatherInput.schema,
  needsApproval: { input, ctx in
    // e.g. require approval for non-local requests
    input.city.lowercased() != "san francisco"
  },
  onInputStart: { _ in },
  onInputDelta: { _, _ in },
  onInputAvailable: { input, _ in print("Tool input:", input) },
  execute: { input, _ in
    .final(.init(celsius: 18.2, condition: "Cloudy"))
  }
)

var tools = ToolRegistry()
tools.register(ToolID<WeatherInput, WeatherOutput>("weather"), weatherTool)

let agent = ToolLoopAgent(
  id: "weather-agent",
  model: model,
  instructions: .text("You are a helpful assistant."),
  tools: tools,
  toolChoice: .auto,
  stopWhen: [Stop.stepCountIs(20)],
  output: Output.text(),
  prepareCall: nil
)

let result = try await agent.generate(prompt: "What's the weather in Paris?")
print(result.text)
```

### 4) `streamText` with partial output streaming

```swift
let stream = streamText(.init(
  model: model,
  prompt: "Return JSON: {\"value\": \"Hello, world!\"}",
  stopWhen: [Stop.stepCountIs(1)],
  output: Output.json()
))

Task {
  for try await delta in stream.textStream {
    print("Δ", delta)
  }
}

Task {
  for try await partial in stream.partialOutputStream {
    print("partial", partial)
  }
}

let final = try await stream.output
print("final", final)
```

---

## Open questions (to resolve before implementation)

1. **Schema ergonomics:** macro-first (`AIKitMacros` package) with `ObjectSchema.manual` as the only escape hatch for external types.
2. **Typed partials:** confirm whether `partialOutputStream` should default to `T.Partial` (strongly typed) or remain `JSONValue` unless explicitly requested.
