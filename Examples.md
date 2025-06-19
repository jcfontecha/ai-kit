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

### Basic ObjectSchema Usage

```swift
import AIKit

struct Recipe: Codable {
    let name: String
    let ingredients: [String]
    let instructions: [String]
    let prepTime: Int
    let difficulty: String
}

let openai = OpenAIProvider(apiKey: "...")
let model = openai.languageModel("gpt-4")
let client = AIKit.client()

// Basic automatic schema generation
let basicSchema = ObjectSchema<Recipe>()

let response = try await client.generateObject(
    model,
    prompt: "Create a chocolate chip cookie recipe",
    schema: basicSchema
)

let recipe: Recipe = response.object
```

### ObjectSchema with Field Descriptions

```swift
// Enhanced schema with field descriptions for better AI generation
let enhancedSchema = ObjectSchema<Recipe>()
    .describe(\.name, "Recipe name that is descriptive and appealing")
    .describe(\.ingredients, "List of ingredients with specific quantities and measurements")
    .describe(\.instructions, "Clear step-by-step cooking instructions")
    .describe(\.prepTime, "Preparation time in minutes", minimum: 1, maximum: 480)
    .describe(\.difficulty, "Cooking difficulty level", enum: ["easy", "medium", "hard"])

let response = try await client.generateObject(
    model,
    prompt: "Create a beginner-friendly chocolate chip cookie recipe",
    schema: enhancedSchema
)
```

### Complex ObjectSchema Example

```swift
struct Product: Codable {
    let name: String
    let price: Double
    let category: String
    let description: String
    let tags: [String]
    let inStock: Bool
    let rating: Double?
}

let productSchema = ObjectSchema<Product>()
    .describe(\.name, "Product name", minLength: 1, maxLength: 100)
    .describe(\.price, "Price in USD", minimum: 0.01, maximum: 10000.0)
    .describe(\.category, "Product category", enum: ["electronics", "books", "clothing", "home"])
    .describe(\.description, "Product description", minLength: 10, maxLength: 500)
    .describe(\.tags, "Product tags for search", maxItems: 10)
    .describe(\.inStock, "Whether product is currently available")
    .describe(\.rating, "Optional customer rating from 1-5", minimum: 1.0, maximum: 5.0)

let productResponse = try await client.generateObject(
    model,
    prompt: "Create a product listing for a wireless headphone",
    schema: productSchema
)
```

### Nested ObjectSchema Example

```swift
struct Address: Codable {
    let street: String
    let city: String
    let state: String
    let zipCode: String
}

struct Person: Codable {
    let name: String
    let age: Int
    let email: String?
    let address: Address
    let hobbies: [String]
}

let personSchema = ObjectSchema<Person>()
    .describe(\.name, "Full name", minLength: 2, maxLength: 50)
    .describe(\.age, "Age in years", minimum: 0, maximum: 150)
    .describe(\.email, "Optional email address in valid format")
    .describe(\.address, "Home address information")
    .describe(\.hobbies, "List of hobbies and interests", maxItems: 5)

let personResponse = try await client.generateObject(
    model,
    prompt: "Generate a profile for a software developer",
    schema: personSchema
)
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