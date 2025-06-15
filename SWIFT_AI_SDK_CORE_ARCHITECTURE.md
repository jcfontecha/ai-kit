# Swift AI SDK - Core Architecture

A clean, Swift-native implementation following Vercel AI SDK patterns with clear separation of concerns.

## Architecture Overview

```
┌─────────────┐    ┌──────────────┐    ┌─────────────────┐
│   AIClient  │───▶│ LanguageModel│───▶│   AIProvider    │
│ (Framework) │    │ (Configuration)│    │ (HTTP Client)   │
└─────────────┘    └──────────────┘    └─────────────────┘
```

## Core Components

### 1. AIClient (Framework Implementation)

The concrete framework that executes all AI operations and contains the core logic.

```swift
public actor AIClient {
    public init(middleware: [any AIMiddleware] = [])
    
    // Core operations that handle everything
    public func generateText(_ model: LanguageModel, messages: [Message]) async throws -> TextResponse
    public func streamText(_ model: LanguageModel, messages: [Message]) -> AsyncThrowingStream<TextChunk, Error>
    public func generateObject<T: Codable>(_ model: LanguageModel, messages: [Message], schema: ObjectSchema<T>) async throws -> ObjectResponse<T>
    public func streamObject<T: Codable>(_ model: LanguageModel, messages: [Message], schema: ObjectSchema<T>) -> AsyncThrowingStream<ObjectChunk<T>, Error>
    
    // Convenience methods for simple prompts
    public func generateText(_ model: LanguageModel, prompt: String) async throws -> TextResponse
    public func streamText(_ model: LanguageModel, prompt: String) -> AsyncThrowingStream<TextChunk, Error>
    public func generateObject<T: Codable>(_ model: LanguageModel, prompt: String, schema: ObjectSchema<T>) async throws -> ObjectResponse<T>
}
```

**AIClient Responsibilities:**
- Apply middleware chain
- JSON schema validation and parsing
- Tool execution and orchestration
- Framework-level response parsing
- Error handling and retries
- Streaming management
- All framework orchestration logic

### 2. LanguageModel (Configuration)

Pre-configured model instances that contain all the settings needed for execution.

```swift
public struct LanguageModel: Sendable {
    public let provider: any AIProvider
    public let modelId: String
    public let configuration: ModelConfiguration
    
    public init(provider: any AIProvider, modelId: String, configuration: ModelConfiguration = .default) {
        self.provider = provider
        self.modelId = modelId
        self.configuration = configuration
    }
}

public struct ModelConfiguration: Sendable {
    public let temperature: Double?
    public let maxTokens: Int?
    public let topP: Double?
    // ... other parameters
    public let providerSpecific: [String: Any]? // For provider-specific settings
}
```

### 3. AIProvider (Translation Layer)

Protocol that handles the translation between AI SDK standard format and provider-specific APIs, following Vercel AI SDK patterns.

```swift
public protocol AIProvider: Sendable {
    var name: String { get }
    
    // Model factory methods - providers create their own models
    func languageModel(_ modelId: String) -> LanguageModel
    
    // Provider-specific request execution with format translation
    func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse
    func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error>
}

// Provider-specific request/response formats
public struct ProviderRequest: Sendable {
    public let modelId: String
    public let messages: [Message]
    public let configuration: ModelConfiguration
    public let tools: [Tool]?
}

public struct ProviderResponse: Sendable {
    public let content: String
    public let toolCalls: [ToolCall]?
    public let usage: Usage
    public let finishReason: FinishReason
}
```

## How It All Works Together

### Simple Text Generation

```swift
// 1. Provider creates model
let openai = OpenAIProvider(apiKey: "sk-...")
let model = openai.languageModel("gpt-4")

// 2. Client executes with elegance
let client = AIClient()
let response = try await client.generateText(model, prompt: "Explain quantum computing")

print(response.text)
```

### Streaming with Tools

```swift
let openai = OpenAIProvider(apiKey: "sk-...")
let model = openai.languageModel("gpt-4")
    .temperature(0.7)
    .tools([WeatherTool(), CalculatorTool()])

let client = AIClient()
let stream = client.streamText(model, prompt: "What's the weather in SF and what's 15 * 23?")

for try await chunk in stream {
    print(chunk.delta, terminator: "")
    if let toolResult = chunk.toolResult {
        print("Tool executed: \(toolResult)")
    }
}
```

### Object Generation

```swift
struct Recipe: Codable {
    let name: String
    let ingredients: [String]
    let instructions: [String]
}

let anthropic = AnthropicProvider(apiKey: "...")
let model = anthropic.languageModel("claude-3-sonnet")
let client = AIClient()

let response = try await client.generateObject(
    model,
    prompt: "Create a chocolate chip cookie recipe",
    schema: ObjectSchema<Recipe>()
)

let recipe: Recipe = response.object
```

## Data Flow

```
1. User calls client.generateText(model, prompt)
2. Client converts prompt to messages array
3. Client applies request middleware
4. Client calls provider.generateTextRaw(request)
5. Provider transforms request to API format
6. Provider makes HTTP call to AI service
7. Provider parses response to standard format
8. Client applies response middleware
9. Client handles tools (if any)
10. Client validates and returns typed response
```

## Key Benefits

### Clean Separation
- **AIClient**: Framework logic and orchestration
- **LanguageModel**: Configuration and settings
- **AIProvider**: Translation layer between framework and APIs

### Vercel AI SDK Compatibility
- Same request/response patterns
- Compatible middleware system
- Familiar tool execution flow
- Similar streaming approach

### Swift-Native Experience
- Strong typing with generics
- Actor-based concurrency
- AsyncSequence for streaming
- Builder pattern for configuration

## Provider Implementation Example

```swift
public struct OpenAIProvider: AIProvider {
    public let name = "OpenAI"
    
    private let apiKey: String
    private let httpClient: HTTPClient
    
    public init(apiKey: String) {
        self.apiKey = apiKey
        self.httpClient = HTTPClient()
    }
    
    public func languageModel(_ modelId: String) -> LanguageModel {
        return LanguageModel(provider: self, modelId: modelId)
    }
    
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        // Transform AI SDK request to OpenAI format
        let openAIRequest = transformToOpenAIFormat(request)
        
        // Validate settings and apply OpenAI-specific mappings
        let validatedRequest = validateAndMapSettings(openAIRequest)
        
        // Make HTTP call
        let httpResponse = try await httpClient.post(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: validatedRequest
        )
        
        // Parse OpenAI response to AI SDK standard format
        return parseToStandardFormat(httpResponse)
    }
    
    // Provider handles format translation, validation, and API communication
}
```

## Framework vs Provider Responsibilities

| Responsibility | AIClient (Framework) | AIProvider (Translation) |
|---|---|---|
| Middleware execution | ✅ | ❌ |
| JSON schema validation | ✅ | ❌ |
| Tool orchestration | ✅ | ❌ |
| Framework response parsing | ✅ | ❌ |
| Error handling & retries | ✅ | ❌ |
| Streaming management | ✅ | ❌ |
| Model factory methods | ❌ | ✅ |
| Message format transformation | ❌ | ✅ |
| Settings validation & mapping | ❌ | ✅ |
| Tool format conversion | ❌ | ✅ |
| Provider response parsing | ❌ | ✅ |
| HTTP communication | ❌ | ✅ |
| Authentication | ❌ | ✅ |

This architecture provides a clean foundation that's both powerful and easy to understand, following Vercel AI SDK patterns while being thoroughly Swift-native.