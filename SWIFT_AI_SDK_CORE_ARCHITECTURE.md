# Swift AI SDK - Core Architecture

A clean, Swift-native implementation following Vercel AI SDK patterns with framework-centralized structured output handling and lightweight providers.

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
    
    // Structured object generation - type-safe method overloads
    public func generateObject<T: Codable>(_ model: LanguageModel, messages: [Message], schema: ObjectSchema<T>, mode: GenerationMode = .auto) async throws -> ObjectResponse<T>
    public func streamObject<T: Codable>(_ model: LanguageModel, messages: [Message], schema: ObjectSchema<T>, mode: GenerationMode = .auto) -> AsyncThrowingStream<ObjectChunk<T>, Error>
    
    // Array generation - element schema with clear return type
    public func generateArray<T: Codable>(_ model: LanguageModel, messages: [Message], elementSchema: ObjectSchema<T>, mode: GenerationMode = .auto) async throws -> ObjectResponse<[T]>
    public func streamArray<T: Codable>(_ model: LanguageModel, messages: [Message], elementSchema: ObjectSchema<T>, mode: GenerationMode = .auto) -> AsyncThrowingStream<ObjectChunk<[T]>, Error>
    
    // Enum generation - predefined values
    public func generateEnum(_ model: LanguageModel, messages: [Message], values: [String], mode: GenerationMode = .auto) async throws -> ObjectResponse<String>
    public func streamEnum(_ model: LanguageModel, messages: [Message], values: [String], mode: GenerationMode = .auto) -> AsyncThrowingStream<ObjectChunk<String>, Error>
    
    // Convenience methods for simple prompts
    public func generateText(_ model: LanguageModel, prompt: String) async throws -> TextResponse
    public func streamText(_ model: LanguageModel, prompt: String) -> AsyncThrowingStream<TextChunk, Error>
    public func generateObject<T: Codable>(_ model: LanguageModel, prompt: String, schema: ObjectSchema<T>, mode: GenerationMode = .auto) async throws -> ObjectResponse<T>
    public func generateArray<T: Codable>(_ model: LanguageModel, prompt: String, elementSchema: ObjectSchema<T>, mode: GenerationMode = .auto) async throws -> ObjectResponse<[T]>
    public func generateEnum(_ model: LanguageModel, prompt: String, values: [String], mode: GenerationMode = .auto) async throws -> ObjectResponse<String>
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

### 3. AIProvider (Lightweight Translation Layer)

Providers handle only basic text generation and API-specific formatting. The framework manages all structured output logic centrally for consistency and simplicity.

```swift
public protocol AIProvider: Sendable {
    var name: String { get }
    
    // Model factory methods - providers create their own models
    func languageModel(_ modelId: String) -> LanguageModel
    
    // Core text generation methods
    func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse
    func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error>
    
    // Provider capabilities for mode support
    var supportedGenerationModes: Set<GenerationMode> { get }
    var defaultGenerationMode: GenerationMode { get }
    
    // Validation (optional)
    func validateConfiguration(_ configuration: ModelConfiguration) throws
}

// Generation modes for structured output
public enum GenerationMode: String, Sendable {
    case auto = "auto"           // Provider chooses optimal mode
    case json = "json"           // JSON mode with schema constraints  
    case tool = "tool"           // Function calling with schema as parameters
}

// Output strategies for framework internal use
public enum OutputStrategy: String, Sendable {
    case object = "object"       // Single object (default)
    case array = "array"         // Array of objects
    case `enum` = "enum"         // Enum values
    case noSchema = "no-schema"  // Free-form JSON
}

// Enhanced request with mode information
public struct ProviderRequest: Sendable {
    public let modelId: String
    public let messages: [Message]
    public let configuration: ModelConfiguration
    public let tools: [Tool]?
    
    // Mode parameter tells provider how to format the request
    public let mode: ProviderMode
}

// Provider modes map to specific API formatting
public enum ProviderMode: Sendable {
    case regular(tools: [Tool]?, toolChoice: ToolChoice?)
    case objectJSON(schema: JSONSchema, name: String?, description: String?)
    case objectTool(tool: Tool) // Tool with schema as parameters
}

// Standard response (no special object types needed)
public struct ProviderResponse: Sendable {
    public let content: String
    public let toolCalls: [ToolCall]?
    public let finishReason: FinishReason
    public let usage: Usage
    public let providerMetadata: [String: Any]?
}

public struct ProviderChunk: Sendable {
    public let delta: String
    public let toolCallDeltas: [ToolCallDelta]?
    public let finishReason: FinishReason?
    public let usage: Usage?
    public let chunkIndex: Int
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

### Structured Object Generation

The Swift AI SDK supports multiple structured output modes that leverage provider-specific capabilities:

```swift
struct Recipe: Codable {
    let name: String
    let ingredients: [String]
    let instructions: [String]
    let cookingTime: Int
}

let openai = OpenAIProvider(apiKey: "sk-...")
let model = openai.languageModel("gpt-4")
let client = AIClient()

// Single object generation - clean and type-safe
let response = try await client.generateObject(
    model,
    prompt: "Create a chocolate chip cookie recipe",
    schema: ObjectSchema<Recipe>()
        .name("Recipe")
        .description("A detailed recipe with ingredients and instructions"),
    mode: .auto  // Provider chooses optimal approach
)

// Explicit mode control still available
let jsonResponse = try await client.generateObject(
    model,
    prompt: "Create a chocolate chip cookie recipe", 
    schema: ObjectSchema<Recipe>()
        .name("Recipe")
        .description("A recipe object"),
    mode: .json  // Forces JSON mode with schema validation
)

let recipe: Recipe = response.object
```

#### Array Generation

```swift
struct Ingredient: Codable {
    let name: String
    let amount: String
    let category: String
}

// Array generation - impossible to misuse, element schema is clear
let ingredients = try await client.generateArray(
    model,
    prompt: "List 10 baking ingredients",
    elementSchema: ObjectSchema<Ingredient>()
        .name("Ingredient")
        .description("A baking ingredient with details"),
    mode: .auto
)

let ingredientList: [Ingredient] = ingredients.object
```

#### Schema-Guided Generation

```swift
// Complex nested schemas with validation
struct DetailedRecipe: Codable {
    let metadata: RecipeMetadata
    let ingredients: [Ingredient]
    let steps: [CookingStep]
    let nutrition: NutritionFacts?
}

// Complex object generation
let detailedResponse = try await client.generateObject(
    model,
    messages: conversationHistory,
    schema: ObjectSchema<DetailedRecipe>()
        .name("DetailedRecipe")
        .description("A comprehensive recipe with full details"),
    mode: .auto  // Provider optimizes based on schema complexity
)

// Enum generation for classification tasks - clean and obvious
let genre = try await client.generateEnum(
    model,
    prompt: "Classify this movie: 'A group of astronauts travel through a wormhole...'",
    values: ["action", "comedy", "drama", "horror", "sci-fi"]
)
```

#### Implementation Notes

The type-safe method overloads internally map to the unified provider interface:

```swift
// generateObject -> calls with output: .object
// generateArray -> calls with output: .array  
// generateEnum -> calls with output: .enum

// All methods delegate to the core implementation:
private func generateObjectInternal<T: Codable>(
    _ model: LanguageModel,
    messages: [Message], 
    schema: ObjectSchema<T>,
    output: OutputStrategy,
    mode: GenerationMode = .auto
) async throws -> ObjectResponse<T>
```

## Data Flow

### **Structured Output Flow**

```
📱 User API Call
  ↓
🏗️  AIClient (Framework) - Entry Point
  │ ┌─ generateObject(model, messages, schema, mode)
  │ ├─ Applies request middleware
  │ ├─ Determines provider mode (auto→json/tool)
  │ ├─ Creates ProviderRequest with mode info
  │ └─ Calls provider.generateTextRaw(request)
  ↓
🔌 AIProvider (Translation) - Lightweight
  │ ┌─ Receives ProviderRequest with mode
  │ ├─ Mode: .objectJSON → formats with response_format
  │ ├─ Mode: .objectTool → formats with function calling
  │ ├─ Makes HTTP call to AI service
  │ └─ Returns raw ProviderResponse (just text)
  ↓
🏗️  AIClient (Framework) - Processing
  │ ┌─ Receives raw text response
  │ ├─ Extracts JSON from response content
  │ ├─ Parses JSON to Swift type
  │ ├─ Validates against ObjectSchema
  │ ├─ Handles errors (malformed JSON, schema mismatch)
  │ ├─ Applies response middleware
  │ └─ Returns typed ObjectResponse<T>
  ↓
📱 User receives strongly-typed result
```

### **Text Generation Flow**

```
1. User calls client.generateText(model, prompt)
2. Client converts prompt to messages array
3. Client applies request middleware
4. Client calls provider.generateTextRaw(request) with mode: .regular
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
    
    // Provider capabilities
    public let supportedGenerationModes: Set<GenerationMode> = [.auto, .json, .tool]
    public let defaultGenerationMode: GenerationMode = .json  // OpenAI prefers structured outputs
    
    public init(apiKey: String) {
        self.apiKey = apiKey
        self.httpClient = HTTPClient()
    }
    
    public func languageModel(_ modelId: String) -> LanguageModel {
        return LanguageModel(provider: self, modelId: modelId)
    }
    
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        let openAIRequest = OpenAIChatRequest(
            model: request.modelId,
            messages: transformMessages(request.messages)
        )
        
        // Handle mode-specific formatting (this is where provider expertise matters)
        switch request.mode {
        case .regular(let tools, let toolChoice):
            // Standard text generation
            openAIRequest.tools = tools?.map(transformTool)
            openAIRequest.tool_choice = transformToolChoice(toolChoice)
            
        case .objectJSON(let schema, let name, let description):
            // OpenAI's native structured output
            if supportsStructuredOutputs(modelId: request.modelId) {
                openAIRequest.response_format = .json_schema(
                    name: name ?? "response", 
                    schema: schema,
                    strict: true,
                    description: description
                )
            } else {
                // Fallback to JSON mode for older models
                openAIRequest.response_format = .json_object
                // Framework will inject schema instruction in prompt
            }
            
        case .objectTool(let tool):
            // Function calling with schema as parameters
            openAIRequest.tools = [transformTool(tool)]
            openAIRequest.tool_choice = .required(tool.function.name)
        }
        
        let httpResponse = try await httpClient.post("/v1/chat/completions", body: openAIRequest)
        return parseToStandardFormat(httpResponse)
    }
    
    // Much simpler streaming - same pattern
    public func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
        // Similar implementation with mode handling
        // Provider just handles HTTP streaming, framework handles JSON parsing
    }
    
    // Simple helper methods - no complex object logic
    private func supportsStructuredOutputs(modelId: String) -> Bool {
        return ["gpt-4o", "gpt-4o-mini"].contains(modelId)
    }
    
    private func parseToStandardFormat(_ httpResponse: OpenAIResponse) -> ProviderResponse {
        // Simple conversion - no JSON schema validation here
        return ProviderResponse(
            content: httpResponse.choices[0].message.content ?? "",
            toolCalls: httpResponse.choices[0].message.tool_calls?.map(transformToolCall),
            finishReason: transformFinishReason(httpResponse.choices[0].finish_reason),
            usage: transformUsage(httpResponse.usage)
        )
    }
}

// Even simpler Anthropic provider - only supports tool mode
public struct AnthropicProvider: AIProvider {
    public let name = "Anthropic"
    public let supportedGenerationModes: Set<GenerationMode> = [.tool]  // Only tool mode
    public let defaultGenerationMode: GenerationMode = .tool
    
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        switch request.mode {
        case .objectJSON:
            // Anthropic doesn't support JSON mode for structured output
            throw AIProviderError.unsupportedParameter("mode", "Anthropic only supports tool mode for structured output")
            
        case .objectTool(let tool):
            // Use Claude's tool calling with schema
            let anthropicRequest = AnthropicRequest(
                model: request.modelId,
                messages: transformMessages(request.messages),
                tools: [transformTool(tool)],
                tool_choice: .specific(tool.function.name)
            )
            
        case .regular(let tools, let toolChoice):
            // Standard text generation
            // ... similar pattern
        }
        
        // Simple HTTP call and response transformation
        let httpResponse = try await httpClient.post("/v1/messages", body: anthropicRequest)
        return parseToStandardFormat(httpResponse)
    }
}
```

## Framework vs Provider Responsibilities

| Responsibility | AIClient (Framework) | AIProvider (Lightweight) |
|---|---|---|
| **Framework Logic** | | |
| Middleware execution | ✅ | ❌ |
| JSON parsing & validation | ✅ | ❌ |
| Schema conversion & validation | ✅ | ❌ |
| Tool orchestration | ✅ | ❌ |
| Error handling & retries | ✅ | ❌ |
| Streaming management | ✅ | ❌ |
| Object type parsing (T.self) | ✅ | ❌ |
| Mode selection (.auto → .json/.tool) | ✅ | ❌ |
| Provider Translation | | |
| Model factory methods | ❌ | ✅ |
| HTTP communication | ❌ | ✅ |
| Authentication | ❌ | ✅ |
| Message format transformation | ❌ | ✅ |
| Mode-specific API formatting | ❌ | ✅ |
| Provider response parsing | ❌ | ✅ |
| Capabilities | | |
| Supported modes declaration | ❌ | ✅ |
| Default mode selection | ❌ | ✅ |
| Settings validation & mapping | ❌ | ✅ |

This architecture mirrors the proven Vercel AI SDK approach while providing a clean, Swift-native foundation that's both powerful and maintainable.