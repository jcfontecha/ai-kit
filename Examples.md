# Swift AI SDK - Usage Examples

This file demonstrates how to use the Swift AI SDK with the new architecture.

## Simple Text Generation

```swift
import ai_swift

// 1. Provider creates model
let openai = OpenAIProvider(apiKey: "sk-...")  // This would be a real provider
let model = openai.languageModel("gpt-4")

// 2. Client executes with elegance
let client = AISwift.client()
let response = try await client.generateText(model, prompt: "Explain quantum computing")

print(response.text)
```

## Streaming with Tools (Future Implementation)

```swift
import ai_swift

let openai = OpenAIProvider(apiKey: "sk-...")
let model = openai.languageModel("gpt-4")
    .temperature(0.7)
    .tools([WeatherTool(), CalculatorTool()])

let client = AISwift.client()
let stream = client.streamText(model, prompt: "What's the weather in SF and what's 15 * 23?")

for try await chunk in stream {
    print(chunk.delta, terminator: "")
    if let toolResult = chunk.toolResult {
        print("Tool executed: \(toolResult)")
    }
}
```

## Object Generation

```swift
import ai_swift

struct Recipe: Codable {
    let name: String
    let ingredients: [String]
    let instructions: [String]
}

let anthropic = AnthropicProvider(apiKey: "...")  // This would be a real provider
let model = anthropic.languageModel("claude-3-sonnet")
let client = AISwift.client()

let response = try await client.generateObject(
    model,
    prompt: "Create a chocolate chip cookie recipe",
    schema: ObjectSchema<Recipe>()
)

let recipe: Recipe = response.object
```

## Current Mock Implementation

For now, you can test with the mock provider:

```swift
import ai_swift

// Create a mock provider for testing
let provider = AISwift.mockProvider()
let model = provider.languageModel("mock-model-1")
    .temperature(0.8)
    .maxTokens(150)

let client = AISwift.client()

// This will work with mock responses
let response = try await client.generateText(model, prompt: "Hello, world!")
print(response.text)  // Outputs: "Mock response to: Hello, world!"
```

## Configuration Examples

```swift
import ai_swift

// Using predefined configurations
let creativeModel = model.temperature(0.9).topP(0.9)
let preciseModel = model.temperature(0.1).topP(0.1)
let balancedModel = model.temperature(0.5).topP(0.5)

// Provider-specific settings
let modelWithSpecific = model.providerSpecific([
    "custom_param": "value",
    "another_param": "another_value"
])
```

## Message Building

```swift
import ai_swift

// Simple message creation
let messages = [
    Message.system("You are a helpful assistant"),
    Message.user("What is the capital of France?"),
    Message.assistant("The capital of France is Paris.")
]

let response = try await client.generateText(model, messages: messages)
```

## Architecture Benefits

This new architecture provides:

1. **Clean Separation**: AIClient handles framework logic, LanguageModel contains configuration, AIProvider handles translation
2. **Vercel AI SDK Compatibility**: Same request/response patterns and middleware system
3. **Swift-Native Experience**: Strong typing, actor-based concurrency, AsyncSequence for streaming

The framework is now ready for implementing real providers like OpenAI, Anthropic, etc.