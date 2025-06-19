# Swift AI SDK

A comprehensive Swift framework for AI model interactions, inspired by the Vercel AI SDK. Provides type-safe, protocol-oriented interfaces for text generation, object generation, embeddings, and streaming operations with built-in middleware support.

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20|%20macOS%20|%20watchOS%20|%20tvOS-blue.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Features

- 🎯 **Type-Safe API**: Comprehensive Swift types with full Codable support
- 🔄 **Streaming Support**: Real-time text and object generation with AsyncSequence
- 🛠️ **Tool Integration**: Function calling with automatic execution
- 📋 **Structured Output**: Automatic schema generation with field descriptions and validation  
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

AIKit's ObjectSchema system provides automatic schema generation from Swift types with field-level descriptions for improved AI generation quality:

```swift
struct Recipe: Codable {
    let name: String
    let ingredients: [String]
    let instructions: [String]
    let prepTime: Int
    let difficulty: String
}

// Automatic schema generation with field descriptions
let schema = ObjectSchema<Recipe>()
    .describe(\.name, "Recipe name that is descriptive and appealing")
    .describe(\.ingredients, "List of ingredients with specific quantities")
    .describe(\.instructions, "Step-by-step cooking instructions")
    .describe(\.prepTime, "Preparation time in minutes", minimum: 1, maximum: 480)
    .describe(\.difficulty, "Cooking difficulty level", enum: ["easy", "medium", "hard"])

let response = try await client.generateObject(
    model, 
    prompt: "Create a chocolate chip cookie recipe",
    schema: schema
)

let recipe: Recipe = response.object
print("Recipe: \(recipe.name)")
```

#### ObjectSchema Features

- **Automatic Generation**: `ObjectSchema<T>()` automatically generates JSON schemas from Swift types
- **Field Descriptions**: Improve AI generation quality with `.describe()` for each field
- **Type Constraints**: Add validation rules like `minimum`, `maximum`, `enum` values
- **Provider Agnostic**: Works seamlessly across OpenAI, Anthropic, and Google providers
- **Swift-Idiomatic**: Uses KeyPath-based APIs for type safety and IDE completion

### Tool Calling

```swift
// Define a tool
let weatherTool = Tool.function(
    name: "get_weather",
    description: "Get current weather for a location",
    parameters: .object(properties: [
        "location": .string(description: "City and state, e.g. San Francisco, CA")
    ], required: ["location"])
)

// Use with model (future implementation)
let modelWithTools = model.tools([weatherTool])
let response = try await client.generateText(modelWithTools, prompt: "What's the weather in Tokyo?")
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