# Quick Start Guide

This guide will get you up and running with AIKit in minutes.

## Your First AIKit Application

### Step 1: Import AIKit

```swift
import AIKit
```

### Step 2: Create a Provider and Model

```swift
// For testing, use the MockProvider
let provider = MockProvider()

// In production, use real providers like:
// let provider = OpenAIProvider(apiKey: "your-api-key")
// let provider = AnthropicProvider(apiKey: "your-api-key")

let model = provider.languageModel("gpt-4")
    .temperature(0.7)
    .maxTokens(100)
```

### Step 3: Create an AIKit Client

```swift
let client = AIKit.client()
```

### Step 4: Generate Text

```swift
Task {
    do {
        let response = try await client.generateText(
            model, 
            prompt: "Write a haiku about Swift programming"
        )
        print(response.text)
    } catch {
        print("Error: \\(error)")
    }
}
```

## Complete Example

Here's a complete, runnable example:

```swift
import AIKit

class AIKitExample {
    func runExample() async {
        // Create provider and model
        let provider = MockProvider()
        let model = provider.languageModel("gpt-4")
            .temperature(0.8)
            .maxTokens(150)
        
        // Create client
        let client = AIKit.client()
        
        do {
            // Generate text
            print("Generating haiku...")
            let response = try await client.generateText(
                model, 
                prompt: "Write a haiku about Swift programming"
            )
            
            print("Generated text:")
            print(response.text)
            print("\\nTokens used: \\(response.usage.totalTokens)")
            
        } catch {
            print("Error generating text: \\(error)")
        }
    }
}

// Usage
let example = AIKitExample()
await example.runExample()
```

## Key Concepts

### Providers
Providers handle the communication with AI services:
- `MockProvider`: For testing and development
- `OpenAIProvider`: For OpenAI GPT models
- `AnthropicProvider`: For Anthropic Claude models

### Models
Models represent specific AI models with configuration:
- Model ID (e.g., "gpt-4", "claude-3-sonnet")
- Parameters (temperature, max tokens, etc.)
- Provider-specific settings

### Clients
The AIKit client orchestrates requests and handles:
- Request/response processing
- Middleware execution
- Error handling
- Streaming

## Common Patterns

### Using Environment Variables

```swift
import Foundation

let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
let provider = OpenAIProvider(apiKey: apiKey)
```

### Error Handling

```swift
do {
    let response = try await client.generateText(model, prompt: "Hello")
} catch AIError.invalidModel(let message) {
    print("Invalid model: \\(message)")
} catch AIError.rateLimitExceeded(let retryAfter) {
    print("Rate limited. Retry after \\(retryAfter) seconds")
} catch {
    print("Unexpected error: \\(error)")
}
```

### Multiple Messages

```swift
let messages = [
    Message.system("You are a helpful assistant"),
    Message.user("What is Swift?"),
    Message.assistant("Swift is a programming language..."),
    Message.user("Tell me more about its features")
]

let response = try await client.generateText(model, messages: messages)
```

## Next Steps

Now that you have the basics working, explore these guides:

- [Text Generation](../guides/text-generation.md) - Advanced text generation
- [Streaming](../guides/streaming.md) - Real-time responses
- [Object Generation](../guides/object-generation.md) - Structured data
- [Configuration](configuration.md) - Model and client configuration

## Common Issues

### Mock Provider Responses
The `MockProvider` returns predefined responses for testing. For real AI responses, use providers like `OpenAIProvider` with valid API keys.

### Async/Await
All AIKit operations are asynchronous. Make sure to use `await` and handle errors appropriately.

### API Keys
Never hardcode API keys in your source code. Use environment variables or secure storage solutions.

```swift
// ❌ Don't do this
let provider = OpenAIProvider(apiKey: "sk-...")

// ✅ Do this instead
let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
guard !apiKey.isEmpty else {
    fatalError("OPENAI_API_KEY environment variable not set")
}
let provider = OpenAIProvider(apiKey: apiKey)
```