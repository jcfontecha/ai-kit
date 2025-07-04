# Swift AI SDK

A comprehensive Swift framework for AI model interactions, inspired by the Vercel AI SDK. Provides type-safe, protocol-oriented interfaces for text generation, object generation, embeddings, and streaming operations with built-in middleware support.

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20|%20macOS%20|%20watchOS%20|%20tvOS-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Features

- 🎯 **Type-Safe API**: Comprehensive Swift types with full Codable support
- 🔄 **Streaming Support**: Real-time text and object generation with AsyncSequence
- 🛠️ **Tool Integration**: Function calling with automatic execution
- 🏗️ **@AIModel Macro**: Clean, declarative schema definition with zero boilerplate
- ✅ **Type-Safe Schemas**: Compile-time verified schemas with automatic nesting
- 🔌 **Provider Agnostic**: Clean abstraction over multiple AI providers
- 🧬 **Middleware System**: Extensible request/response transformation
- 🏗️ **Vercel AI SDK Compatible**: Familiar patterns for web developers
- ⚡ **Swift-Native**: Actor-based concurrency, builder patterns, and strong typing

## Architecture

The Swift AI SDK follows a clean three-layer architecture:

```
┌─────────────┐    ┌──────────────┐    ┌─────────────────┐
│   AIClient  │───▶│ LanguageModel│───▶│   AIProvider    │
│ (Framework) │    │ (Configuration)│    │ (Translation)   │
└─────────────┘    └──────────────┘    └─────────────────┘
```

### Core Components

- **AIClient**: Framework implementation that handles orchestration, middleware, tool execution, and streaming
- **LanguageModel**: Configuration container with provider, model ID, and parameters  
- **AIProvider**: Translation layer between SDK standard format and provider APIs

## Quick Start

### Installation

Add AIKit to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/jcfontecha/ai-kit.git", from: "1.0.0")
]
```

Or add it directly in Xcode:
1. File → Add Package Dependencies
2. Enter the repository URL: `https://github.com/jcfontecha/ai-kit.git`
3. Select the version and add to your target

### Basic Usage

```swift
import AIKit

// Create provider and model
let provider = MockProvider() // Use real providers like OpenAIProvider in production
let model = provider.languageModel("gpt-4")
    .temperature(0.8)
    .maxTokens(150)

// Create client
let client = AIKit.client()

// Generate text
let response = try await client.generateText(model, prompt: "Write a haiku about Swift")
print(response.text)
```

### Streaming

```swift
let stream = client.streamText(model, prompt: "Count from 1 to 10")

for try await chunk in stream {
    print(chunk.delta, terminator: "")
}
```

### Structured Object Generation

AIKit provides two approaches for structured object generation: **@AIModel macro** for your own types and **Manual ObjectSchema** for external types you can't modify.

#### Approach 1: @AIModel Macro (Recommended - 90% of use cases)

The modern, declarative approach with zero boilerplate:

```swift
@AIModel
struct Recipe {
    @Field("Recipe name that is descriptive and appealing", minLength: 1, maxLength: 100)
    let name: String
    
    @Field("List of ingredients with specific quantities", maxItems: 20)
    let ingredients: [String]
    
    @Field("Step-by-step cooking instructions")
    let instructions: [String]
    
    @Field("Preparation time in minutes", range: 1...480)
    let prepTime: Int
    
    @Field("Cooking difficulty level", enum: ["easy", "medium", "hard"])
    let difficulty: String
}

// Clean, type-safe API
let recipe = try await client.generateObject(
    model, 
    prompt: "Create a chocolate chip cookie recipe",
    type: Recipe.self  // That's it!
)

print("Recipe: \(recipe.name)")
```

#### Approach 2: Manual ObjectSchema (For external types only)

When you can't modify a type to add @AIModel:

```swift
struct User: Codable, Sendable {
    let name: String
    let age: Int
    let email: String?
}

// Manual schema with full control
let userSchema = ObjectSchema<User>.manual(
    jsonSchema: .object(properties: [
        "name": .string(minLength: 1, maxLength: 100),
        "age": .integer(minimum: 0, maximum: 150),
        "email": .string(format: "email")
    ], required: ["name", "age"]),
    name: "User",
    description: "A user profile with personal information"
)

let response = try await client.generateObject(
    model, 
    prompt: "Create a user profile",
    schema: userSchema
)

let user: User = response.object
```

#### Advanced @AIModel Examples

**Nested Objects:**
```swift
@AIModel
struct Address {
    @Field("Street address", minLength: 1)
    let street: String
    
    @Field("City name", minLength: 1)
    let city: String
    
    @Field("Country code", minLength: 2, maxLength: 2)
    let country: String
}

@AIModel
struct Company {
    @Field("Company name", minLength: 1, maxLength: 100)
    let name: String
    
    @Field("Company headquarters")
    let address: Address  // Automatic nesting!
    
    @Field("List of employees")
    let employees: [User]
}
```

**Built-in Type Support:**
```swift
// Common types work out of the box
let userId = try await client.generateObject(model, prompt: "Generate a UUID", type: UUID.self)
let timestamp = try await client.generateObject(model, prompt: "Current timestamp", type: Date.self)
let count = try await client.generateObject(model, prompt: "Random number 1-100", type: Int.self)
```

#### Schema Features

- **🏗️ Clean Syntax**: Simple @AIModel macro with @Field annotations
- **✅ Compile-time Safety**: All schemas verified at compile time
- **🔄 Automatic Nesting**: Reference other @AIModel types seamlessly
- **📝 Rich Constraints**: String lengths, numeric ranges, array sizes, enum values
- **🎯 Zero Boilerplate**: Just add @AIModel and you're done
- **🔌 Provider Agnostic**: Works across OpenAI, Anthropic, and Google providers
- **⚡ Performance**: No runtime reflection - all compile-time

### Array Generation

```swift
// Generate arrays using @AIModel types
let users = try await client.generateArray(
    model,
    prompt: "Create 3 diverse user profiles",
    elementType: User.self
)

// Or with manual schemas for external types
let recipes = try await client.generateArray(
    model,
    prompt: "Create 5 quick breakfast recipes",
    elementSchema: recipeSchema
)
```

### Tool Calling

AIKit provides automatic tool execution during text generation and streaming, following the same pattern as Vercel AI SDK:

```swift
// Define tools with their execute functions
let weatherTool = Tool(
    function: ToolFunction(
        name: "get_weather",
        description: "Get current weather for a location",
        parameters: JSONSchema.object(properties: [
            "location": .string(description: "City and state, e.g. San Francisco, CA"),
            "units": .string(enum: ["celsius", "fahrenheit"])
        ], required: ["location"])
    ),
    execute: { toolCall in
        // Extract parameters
        let args = toolCall.function.parsedArguments ?? [:]
        let location = args["location"] as? String ?? "Unknown"
        let units = args["units"] as? String ?? "celsius"
        
        // Simulate weather API call
        let temperature = units == "celsius" ? "22°C" : "72°F"
        return ToolResult(
            toolCallId: toolCall.id,
            result: .text("The weather in \(location) is \(temperature) and sunny")
        )
    }
)

// Tools execute automatically during generation
let response = try await client.generateText(
    model,
    messages: [Message.user("What's the weather in Tokyo?")],
    tools: [weatherTool]
)

print(response.text) // "The weather in Tokyo is 22°C and sunny"
```

#### Tool Definition with @AIModel

```swift
@AIModel
struct SearchQuery {
    @Field("Search terms")
    let query: String
    
    @Field("Maximum number of results", range: 1...100)
    let maxResults: Int
}

let searchTool = Tool(
    function: ToolFunction(
        name: "search_notes",
        description: "Search through notes",
        parameters: SearchQuery.schema.jsonSchema
    ),
    execute: { toolCall in
        let args = toolCall.function.parsedArguments ?? [:]
        let query = args["query"] as? String ?? ""
        let maxResults = args["maxResults"] as? Int ?? 10
        
        // Perform search
        let results = performSearch(query: query, limit: maxResults)
        return ToolResult(
            toolCallId: toolCall.id,
            result: .text("Found \(results.count) notes matching '\(query)'")
        )
    }
)
```

#### Streaming with Automatic Tool Execution

```swift
// Tools execute automatically during streaming too
let stream = client.streamText(
    model,
    messages: [Message.user("Search for Swift tutorials and tell me about them")],
    tools: [searchTool],
    maxSteps: 3  // Allow up to 3 tool executions
)

for try await chunk in stream {
    print(chunk.delta, terminator: "")
}
```

## File Structure

The SDK is organized into focused modules:

```
Sources/AIKit/
├── Core/                           # Core architecture components
│   ├── AIClient.swift             # Main framework implementation
│   ├── AIProvider.swift           # Provider protocol and capabilities
│   ├── LanguageModel.swift        # Model configuration container
│   ├── ModelConfiguration.swift   # Parameter configuration
│   └── Middleware.swift           # Middleware system
├── Types/                          # Data types and schemas
│   ├── Messages.swift             # Message and conversation types
│   ├── Tools.swift                # Tool calling system
│   ├── Usage.swift                # Token usage and billing
│   ├── Responses.swift            # Response types (TextResponse, ObjectResponse)
│   ├── ProviderTypes.swift        # Provider request/response types
│   ├── ObjectSchema.swift         # Structured object schemas
│   ├── SchemaProviding.swift      # Modern schema DSL and protocol
│   ├── Streaming.swift            # Streaming types and utilities
│   ├── Errors.swift               # Error types
│   └── JSONSchema.swift           # JSON schema definitions
├── Extensions/
│   └── ConvenienceExtensions.swift # Builder patterns and utilities
├── Providers/
│   └── MockProvider.swift         # Mock provider for testing
└── AIKit.swift                    # Main module interface
```

## Configuration

### Model Parameters

```swift
let model = provider.languageModel("gpt-4")
    .temperature(0.7)           // Controls randomness (0.0-1.0)
    .maxTokens(500)            // Maximum tokens to generate
    .topP(0.9)                 // Nucleus sampling threshold
    .frequencyPenalty(0.3)     // Reduce repetition
    .stopSequences(["END"])    // Stop generation sequences
```

### Predefined Configurations

```swift
// For creative writing
let creative = AIKit.creativeConfiguration
let model = provider.languageModel("gpt-4").configure { creative }

// For precise, factual responses  
let precise = AIKit.preciseConfiguration

// Balanced general-purpose
let balanced = AIKit.balancedConfiguration
```

### Provider-Specific Settings

```swift
let model = provider.languageModel("gpt-4")
    .providerSpecific([
        "logit_bias": "{\\"50256\\": -100}",
        "custom_param": "value"
    ])
```

## Advanced Features

### Middleware

```swift
// Add logging
let client = AIKit.client(middleware: [
    AIKit.loggingMiddleware(),
    AIKit.rateLimitMiddleware(maxRequests: 100),
    AIKit.retryMiddleware(maxRetries: 3)
])
```

### Message Building

```swift
let messages = [
    Message.system("You are a helpful coding assistant"),
    Message.user("Explain async/await in Swift"),
    Message.assistant("Async/await in Swift provides..."),
    Message.user("Can you show an example?")
]

let response = try await client.generateText(model, messages: messages)
```

### Stream Processing

```swift
// Collect full text from stream
let fullText = try await stream.collectText()

// Process only deltas
let deltaStream = stream.deltas()
for try await delta in deltaStream {
    updateUI(with: delta)
}
```

### Error Handling

```swift
do {
    let response = try await client.generateText(model, prompt: "Hello")
} catch AIProviderError.rateLimitExceeded(let retryAfter) {
    print("Rate limited. Retry after \(retryAfter) seconds")
} catch AIError.invalidResponse(let message) {
    print("Invalid response: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Provider Implementation

To implement a new provider, conform to the `AIProvider` protocol:

```swift
public struct OpenAIProvider: AIProvider {
    public let name = "OpenAI"
    private let apiKey: String
    
    public init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    public func languageModel(_ modelId: String) -> LanguageModel {
        return LanguageModel(provider: self, modelId: modelId)
    }
    
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        // Transform request to OpenAI format
        // Make HTTP call
        // Transform response to standard format
    }
    
    public func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
        // Implement streaming
    }
}
```

## Testing

The SDK includes comprehensive testing utilities:

```swift
// Use mock provider for testing
let mockProvider = AIKit.mockProvider()
let testModel = mockProvider.languageModel("test-model")

// Configure mock behavior
let mockConfig = MockConfiguration(
    responseDelay: 0.1,
    errorRate: 0.05
)
let provider = MockProvider(configuration: mockConfig)
```

Run tests:

```bash
swift test
```

## Roadmap

- [ ] OpenAI Provider Implementation
- [ ] Anthropic Provider Implementation  
- [ ] Google AI Provider Implementation
- [ ] Embedding Support
- [ ] Image Generation
- [ ] Function Calling Implementation
- [ ] Caching Middleware
- [ ] Observability Integration

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by the [Vercel AI SDK](https://github.com/vercel/ai)
- Built with Swift's modern concurrency features
- Follows Swift API design guidelines