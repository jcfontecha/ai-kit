# AIClient API Reference

The `AIClient` is the main interface for interacting with AI models in AIKit. It handles orchestration, middleware execution, streaming, and error management.

## Overview

`AIClient` is an actor that provides thread-safe access to AI operations. It supports text generation, object generation, streaming, and tool execution.

```swift
public actor AIClient {
    // Main interface methods
}
```

## Creating an AIClient

### Default Client

```swift
let client = AIKit.client()
```

### Client with Middleware

```swift
let client = AIKit.client(middleware: [
    AIKit.loggingMiddleware(),
    AIKit.rateLimitMiddleware(maxRequests: 100),
    AIKit.retryMiddleware(maxRetries: 3)
])
```

### Client with Configuration

```swift
let configuration = AIClientConfiguration(
    timeout: 30.0,
    maxRetries: 3,
    defaultMiddleware: true
)
let client = AIKit.client(configuration: configuration)
```

## Text Generation Methods

### generateText(model:prompt:)

Generates text from a simple prompt.

```swift
func generateText(
    _ model: LanguageModel,
    prompt: String
) async throws -> TextResponse
```

**Parameters:**
- `model`: The configured language model to use
- `prompt`: The text prompt to send to the model

**Returns:** `TextResponse` containing generated text and metadata

**Example:**
```swift
let response = try await client.generateText(
    model,
    prompt: "Explain Swift optionals"
)
print(response.text)
```

### generateText(model:messages:)

Generates text from a conversation history.

```swift
func generateText(
    _ model: LanguageModel,
    messages: [Message]
) async throws -> TextResponse
```

**Parameters:**
- `model`: The configured language model to use
- `messages`: Array of conversation messages

**Returns:** `TextResponse` containing generated text and metadata

**Example:**
```swift
let messages = [
    Message.system("You are a helpful assistant"),
    Message.user("What is Swift?")
]
let response = try await client.generateText(model, messages: messages)
```

## Streaming Methods

### streamText(model:prompt:)

Streams text generation from a simple prompt.

```swift
func streamText(
    _ model: LanguageModel,
    prompt: String
) -> TextStream
```

**Parameters:**
- `model`: The configured language model to use
- `prompt`: The text prompt to send to the model

**Returns:** `TextStream` that yields `StreamChunk` objects

**Example:**
```swift
let stream = client.streamText(model, prompt: "Write a story")

for try await chunk in stream {
    print(chunk.delta, terminator: "")
}
```

### streamText(model:messages:)

Streams text generation from conversation messages.

```swift
func streamText(
    _ model: LanguageModel,
    messages: [Message]
) -> TextStream
```

**Parameters:**
- `model`: The configured language model to use
- `messages`: Array of conversation messages

**Returns:** `TextStream` that yields `StreamChunk` objects

## Object Generation Methods

### generateObject(model:prompt:schema:)

Generates a structured object from a prompt.

```swift
func generateObject<T: Codable>(
    _ model: LanguageModel,
    prompt: String,
    schema: ObjectSchema<T>
) async throws -> ObjectResponse<T>
```

**Parameters:**
- `model`: The configured language model to use
- `prompt`: The text prompt describing the desired object
- `schema`: Schema definition for the target type

**Returns:** `ObjectResponse<T>` containing the generated object

**Example:**
```swift
struct Recipe: Codable {
    let name: String
    let ingredients: [String]
}

let schema = ObjectSchema<Recipe>()
let response = try await client.generateObject(
    model,
    prompt: "Create a chocolate cake recipe",
    schema: schema
)
let recipe = response.object
```

### generateObject(model:messages:schema:)

Generates a structured object from conversation messages.

```swift
func generateObject<T: Codable>(
    _ model: LanguageModel,
    messages: [Message],
    schema: ObjectSchema<T>
) async throws -> ObjectResponse<T>
```

## Response Types

### TextResponse

Response from text generation operations.

```swift
public struct TextResponse {
    public let text: String
    public let finishReason: FinishReason
    public let usage: Usage
    public let messages: [Message]
    public let metadata: [String: Any]
}
```

**Properties:**
- `text`: The generated text content
- `finishReason`: Why generation stopped
- `usage`: Token usage information
- `messages`: Complete conversation including the response
- `metadata`: Provider-specific additional data

### ObjectResponse<T>

Response from object generation operations.

```swift
public struct ObjectResponse<T: Codable> {
    public let object: T
    public let finishReason: FinishReason
    public let usage: Usage
    public let rawText: String
    public let metadata: [String: Any]
}
```

**Properties:**
- `object`: The generated and parsed object
- `finishReason`: Why generation stopped
- `usage`: Token usage information
- `rawText`: Raw JSON text before parsing
- `metadata`: Provider-specific additional data

### StreamChunk

Individual chunk from streaming operations.

```swift
public struct StreamChunk {
    public let delta: String
    public let usage: Usage?
    public let finishReason: FinishReason?
    public let metadata: [String: Any]
}
```

**Properties:**
- `delta`: New text content since last chunk
- `usage`: Token usage (usually only in final chunk)
- `finishReason`: Why generation stopped (only in final chunk)
- `metadata`: Provider-specific data

## Tool Execution Methods

### generateText with Tools

When tools are provided, AIClient automatically handles tool execution:

```swift
func generateText(
    _ model: LanguageModel,
    messages: [Message],
    tools: [Tool],
    toolChoice: ToolChoice? = nil,
    maxSteps: Int = 1
) async throws -> TextResponse
```

**Parameters:**
- `model`: The configured language model to use
- `messages`: Conversation messages
- `tools`: Available tools with execute functions
- `toolChoice`: How the model should use tools (.auto, .required, .none, .tool(name:))
- `maxSteps`: Maximum number of tool execution steps (default: 1)

**Returns:** `TextResponse` with final result after tool execution

**Example:**
```swift
// Define a tool with its execute function
let weatherTool = Tool(
    function: ToolFunction(
        name: "get_weather",
        description: "Get current weather",
        parameters: JSONSchema.object(properties: [
            "location": .string(description: "City name")
        ], required: ["location"])
    ),
    execute: { toolCall in
        let args = toolCall.function.parsedArguments ?? [:]
        let location = args["location"] as? String ?? "Unknown"
        
        // Simulate weather API call
        return ToolResult(
            toolCallId: toolCall.id,
            result: .text("Weather in \(location): 72°F, sunny")
        )
    }
)

// Tools execute automatically
let response = try await client.generateText(
    model,
    messages: [Message.user("What's the weather in Paris?")],
    tools: [weatherTool]
)

print(response.text) // "The weather in Paris is 72°F and sunny."
```

### streamText with Tools

Streaming also supports automatic tool execution:

```swift
func streamText(
    _ model: LanguageModel,
    messages: [Message],
    tools: [Tool]? = nil,
    toolChoice: ToolChoice? = nil,
    maxSteps: Int = 1
) -> TextStream
```

**Parameters:**
- Same as generateText

**Returns:** `TextStream` that yields chunks including tool execution events

**Example:**
```swift
let stream = client.streamText(
    model,
    messages: [Message.user("Search for Swift tutorials")],
    tools: [searchTool],
    maxSteps: 3
)

for try await chunk in stream {
    // Handle different chunk types
    if let toolCall = chunk.toolCallStreamingStart {
        print("Calling tool: \(toolCall.toolName)")
    }
    
    print(chunk.delta, terminator: "")
}
```

## Error Handling

All `AIClient` methods can throw various `AIError` types:

```swift
do {
    let response = try await client.generateText(model, prompt: "Hello")
} catch AIError.invalidModel(let message) {
    print("Invalid model: \\(message)")
} catch AIError.rateLimitExceeded(let retryAfter) {
    print("Rate limited. Retry after \\(retryAfter) seconds")
} catch AIError.contentFiltered(let reason) {
    print("Content filtered: \\(reason)")
} catch AIError.networkError(let error) {
    print("Network error: \\(error)")
} catch {
    print("Unexpected error: \\(error)")
}
```

## Middleware Integration

AIClient processes middleware in order for both requests and responses:

```swift
// Middleware is applied in this order:
// Request: Middleware 1 → Middleware 2 → Provider
// Response: Provider → Middleware 2 → Middleware 1

let client = AIKit.client(middleware: [
    loggingMiddleware,      // Applied first to requests, last to responses
    rateLimitMiddleware,    // Applied second to requests, second-to-last to responses
    retryMiddleware         // Applied last to requests, first to responses
])
```

## Thread Safety

`AIClient` is an actor, making it thread-safe:

```swift
// Multiple concurrent calls are safe
async let response1 = client.generateText(model, prompt: "First")
async let response2 = client.generateText(model, prompt: "Second")
async let response3 = client.generateText(model, prompt: "Third")

let responses = try await [response1, response2, response3]
```

## Configuration

### AIClientConfiguration

```swift
public struct AIClientConfiguration {
    public let timeout: TimeInterval        // Request timeout (default: 60)
    public let maxRetries: Int             // Maximum retry attempts (default: 0)
    public let defaultMiddleware: Bool      // Include built-in middleware (default: true)
    
    public init(
        timeout: TimeInterval = 60,
        maxRetries: Int = 0,
        defaultMiddleware: Bool = true
    )
}
```

## Best Practices

### 1. Reuse Client Instances

```swift
// ✅ Good: Reuse client
class AIService {
    private let client = AIKit.client()
    
    func generateText(prompt: String) async throws -> String {
        let response = try await client.generateText(model, prompt: prompt)
        return response.text
    }
}

// ❌ Avoid: Creating new clients frequently
func generateText(prompt: String) async throws -> String {
    let client = AIKit.client() // Creates new client each time
    let response = try await client.generateText(model, prompt: prompt)
    return response.text
}
```

### 2. Handle Errors Appropriately

```swift
func robustTextGeneration(prompt: String) async throws -> String {
    do {
        let response = try await client.generateText(model, prompt: prompt)
        return response.text
    } catch AIError.rateLimitExceeded(let retryAfter) {
        // Implement exponential backoff
        try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
        return try await robustTextGeneration(prompt: prompt)
    } catch AIError.contentFiltered {
        // Provide alternative or sanitized prompt
        return try await robustTextGeneration(prompt: sanitizePrompt(prompt))
    } catch {
        // Log error and provide fallback
        logger.error("Text generation failed: \\(error)")
        throw error
    }
}
```

### 3. Use Appropriate Models

```swift
class SmartAIService {
    private let client = AIKit.client()
    private let provider: AIProvider
    
    init(provider: AIProvider) {
        self.provider = provider
    }
    
    func generateText(prompt: String, complexity: TaskComplexity) async throws -> String {
        let model = switch complexity {
        case .simple:
            provider.languageModel("gpt-3.5-turbo").maxTokens(200)
        case .medium:
            provider.languageModel("gpt-4").maxTokens(500)
        case .complex:
            provider.languageModel("gpt-4").maxTokens(1500).temperature(0.3)
        }
        
        let response = try await client.generateText(model, prompt: prompt)
        return response.text
    }
}
```

### 4. Monitor Usage

```swift
extension AIClient {
    func generateTextWithUsageTracking(
        _ model: LanguageModel,
        prompt: String
    ) async throws -> (text: String, usage: Usage) {
        let response = try await generateText(model, prompt: prompt)
        
        // Log usage for monitoring
        logger.info("Tokens used: \\(response.usage.totalTokens)")
        
        return (response.text, response.usage)
    }
}
```

## See Also

- [LanguageModel](language-model.md) - Model configuration
- [AIProvider](ai-provider.md) - Provider implementation
- [Middleware](middleware.md) - Request/response transformation
- [Types](types.md) - Core data types