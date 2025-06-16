# Text Generation

This guide covers all aspects of generating text with AIKit, from basic usage to advanced techniques.

## Overview

Text generation is the most fundamental operation in AIKit. It involves sending a prompt to an AI model and receiving generated text in response.

## Basic Text Generation

### Simple Prompt

```swift
import AIKit

let provider = OpenAIProvider(apiKey: "your-api-key")
let model = provider.languageModel("gpt-4")
let client = AIKit.client()

let response = try await client.generateText(
    model,
    prompt: "Explain quantum computing in simple terms"
)

print(response.text)
print("Tokens used: \\(response.usage.totalTokens)")
```

### With Configuration

```swift
let model = provider.languageModel("gpt-4")
    .temperature(0.7)
    .maxTokens(500)
    .topP(0.9)

let response = try await client.generateText(
    model,
    prompt: "Write a creative story about a robot learning to paint"
)
```

## Working with Messages

### Conversation History

```swift
let messages = [
    Message.system("You are a helpful cooking assistant"),
    Message.user("How do I make pasta?"),
    Message.assistant("To make pasta, you'll need..."),
    Message.user("What about making it gluten-free?")
]

let response = try await client.generateText(model, messages: messages)
```

### Message Types

```swift
// System message - sets behavior/context
let systemMessage = Message.system("You are a professional code reviewer")

// User message - user input
let userMessage = Message.user("Review this Swift code: func add(a: Int, b: Int) -> Int { return a + b }")

// Assistant message - AI response
let assistantMessage = Message.assistant("This function looks good. It's simple and follows Swift conventions.")

// Tool message - tool execution result
let toolMessage = Message.tool(
    toolCallId: "call_123",
    content: "Current weather: 72°F, sunny"
)
```

## Advanced Prompting Techniques

### Few-Shot Learning

```swift
let prompt = \"\"\"
Translate the following to French:

English: Hello, how are you?
French: Bonjour, comment allez-vous?

English: What is your name?
French: Comment vous appelez-vous?

English: I love programming.
French:
\"\"\"

let response = try await client.generateText(model, prompt: prompt)
```

### Chain of Thought

```swift
let prompt = \"\"\"
Question: A restaurant has 15 tables. Each table can seat 4 people. If the restaurant is 80% full, how many people are currently dining?

Let me think step by step:
1. Total capacity = 15 tables × 4 people per table = 60 people
2. 80% full means 0.8 × 60 = 48 people
3. Therefore, 48 people are currently dining.

Question: A library has 8 shelves. Each shelf has 25 books. If 30% of the books are checked out, how many books remain in the library?

Let me think step by step:
\"\"\"

let response = try await client.generateText(model, prompt: prompt)
```

### Role-Based Prompting

```swift
let messages = [
    Message.system(\"\"\"
    You are an expert Swift developer with 10 years of experience. 
    You provide clear, concise code examples and explain best practices.
    Always consider performance, readability, and Swift idioms.
    \"\"\"),
    Message.user("How should I handle network errors in Swift?")
]

let response = try await client.generateText(model, messages: messages)
```

## Response Handling

### Basic Response

```swift
let response = try await client.generateText(model, prompt: "Hello")

print("Generated text: \\(response.text)")
print("Finish reason: \\(response.finishReason)")
print("Usage: \\(response.usage)")
```

### Response Properties

```swift
struct TextResponse {
    let text: String                    // Generated text
    let finishReason: FinishReason     // Why generation stopped
    let usage: Usage                   // Token usage information
    let messages: [Message]            // Full conversation history
    let metadata: [String: Any]        // Provider-specific metadata
}
```

### Finish Reasons

```swift
switch response.finishReason {
case .stop:
    print("Generation completed naturally")
case .length:
    print("Reached maximum token limit")
case .contentFilter:
    print("Content filtered by provider")
case .toolCalls:
    print("Generation stopped for tool execution")
}
```

## Error Handling

### Common Errors

```swift
do {
    let response = try await client.generateText(model, prompt: "Hello")
} catch AIError.invalidModel(let message) {
    print("Invalid model: \\(message)")
} catch AIError.rateLimitExceeded(let retryAfter) {
    print("Rate limited. Retry after \\(retryAfter) seconds")
    // Implement exponential backoff
} catch AIError.contentFiltered(let reason) {
    print("Content was filtered: \\(reason)")
} catch AIError.networkError(let error) {
    print("Network error: \\(error)")
} catch {
    print("Unexpected error: \\(error)")
}
```

### Retry Logic

```swift
func generateTextWithRetry(
    model: LanguageModel,
    prompt: String,
    maxRetries: Int = 3
) async throws -> TextResponse {
    var lastError: Error?
    
    for attempt in 0..<maxRetries {
        do {
            return try await client.generateText(model, prompt: prompt)
        } catch AIError.rateLimitExceeded(let retryAfter) {
            lastError = AIError.rateLimitExceeded(retryAfter)
            let delay = min(pow(2.0, Double(attempt)) + retryAfter, 60.0)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch {
            lastError = error
            break
        }
    }
    
    throw lastError ?? AIError.maxRetriesExceeded
}
```

## Performance Optimization

### Concurrent Requests

```swift
async let response1 = client.generateText(model, prompt: "First prompt")
async let response2 = client.generateText(model, prompt: "Second prompt")
async let response3 = client.generateText(model, prompt: "Third prompt")

let responses = try await [response1, response2, response3]
```

### Batch Processing

```swift
func generateTextBatch(prompts: [String]) async throws -> [TextResponse] {
    return try await withThrowingTaskGroup(of: TextResponse.self) { group in
        for prompt in prompts {
            group.addTask {
                try await client.generateText(model, prompt: prompt)
            }
        }
        
        var responses: [TextResponse] = []
        for try await response in group {
            responses.append(response)
        }
        return responses
    }
}
```

### Caching Responses

```swift
actor ResponseCache {
    private var cache: [String: TextResponse] = [:]
    
    func response(for prompt: String) -> TextResponse? {
        return cache[prompt]
    }
    
    func setResponse(_ response: TextResponse, for prompt: String) {
        cache[prompt] = response
    }
}

let cache = ResponseCache()

func generateTextWithCache(prompt: String) async throws -> TextResponse {
    if let cached = await cache.response(for: prompt) {
        return cached
    }
    
    let response = try await client.generateText(model, prompt: prompt)
    await cache.setResponse(response, for: prompt)
    return response
}
```

## Prompt Engineering Best Practices

### 1. Be Specific

```swift
// ❌ Vague
let prompt = "Write code"

// ✅ Specific
let prompt = \"\"\"
Write a Swift function that takes an array of integers and returns 
the sum of all even numbers. Include error handling for empty arrays.
\"\"\"
```

### 2. Provide Context

```swift
let prompt = \"\"\"
Context: You are helping a beginner Swift developer learn about optionals.

Question: What's the difference between ! and ? in Swift?

Please explain in simple terms with examples.
\"\"\"
```

### 3. Use Examples

```swift
let prompt = \"\"\"
Convert the following variable names from camelCase to snake_case:

camelCase: firstName
snake_case: first_name

camelCase: userAccountId
snake_case: user_account_id

camelCase: backgroundImageUrl
snake_case:
\"\"\"
```

### 4. Structure Your Prompts

```swift
let prompt = \"\"\"
TASK: Code review
LANGUAGE: Swift
FOCUS: Performance and best practices

CODE:
```swift
func processUsers(_ users: [User]) {
    for user in users {
        if user.isActive {
            print(user.name)
        }
    }
}
```

REVIEW:
\"\"\"
```

## Model-Specific Considerations

### OpenAI GPT Models

```swift
// GPT-4 - Best for complex reasoning
let gpt4Model = provider.languageModel("gpt-4")
    .temperature(0.7)
    .maxTokens(2000)

// GPT-3.5-turbo - Good balance of speed and quality
let gpt35Model = provider.languageModel("gpt-3.5-turbo")
    .temperature(0.8)
    .maxTokens(1000)
```

### Anthropic Claude Models

```swift
// Claude-3 Opus - Most capable
let claudeOpusModel = provider.languageModel("claude-3-opus-20240229")
    .temperature(0.6)
    .maxTokens(3000)

// Claude-3 Sonnet - Balanced
let claudeSonnetModel = provider.languageModel("claude-3-sonnet-20240229")
    .temperature(0.7)
    .maxTokens(2000)
```

## Testing Text Generation

### Unit Tests

```swift
import XCTest
@testable import AIKit

class TextGenerationTests: XCTestCase {
    func testBasicTextGeneration() async throws {
        let provider = MockProvider()
        let model = provider.languageModel("test-model")
        let client = AIKit.client()
        
        let response = try await client.generateText(
            model,
            prompt: "Hello"
        )
        
        XCTAssertFalse(response.text.isEmpty)
        XCTAssertEqual(response.finishReason, .stop)
    }
    
    func testErrorHandling() async {
        let provider = MockProvider(shouldFail: true)
        let model = provider.languageModel("test-model")
        let client = AIKit.client()
        
        do {
            _ = try await client.generateText(model, prompt: "Hello")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is AIError)
        }
    }
}
```

### Integration Tests

```swift
class IntegrationTests: XCTestCase {
    func testRealProvider() async throws {
        let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        XCTSkipIf(apiKey?.isEmpty != false, "API key not provided")
        
        let provider = OpenAIProvider(apiKey: apiKey!)
        let model = provider.languageModel("gpt-3.5-turbo")
        let client = AIKit.client()
        
        let response = try await client.generateText(
            model,
            prompt: "Say hello in exactly 2 words"
        )
        
        XCTAssertFalse(response.text.isEmpty)
        XCTAssertLessThanOrEqual(response.text.split(separator: " ").count, 3)
    }
}
```

## Next Steps

- [Streaming](streaming.md) - Learn about real-time text streaming
- [Object Generation](object-generation.md) - Generate structured data
- [Tool Calling](tool-calling.md) - Integrate with external functions
- [Error Handling](error-handling.md) - Robust error management