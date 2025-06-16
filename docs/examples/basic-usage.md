# Basic Usage Examples

This document provides practical examples for common AIKit usage patterns.

## Table of Contents
- [Hello World](#hello-world)
- [Configuration Examples](#configuration-examples)
- [Message Conversations](#message-conversations)
- [Error Handling](#error-handling)
- [Streaming Examples](#streaming-examples)
- [Object Generation](#object-generation)

## Hello World

### Simplest Example

```swift
import AIKit

// Create provider, model, and client
let provider = MockProvider()
let model = provider.languageModel("gpt-4")
let client = AIKit.client()

// Generate text
let response = try await client.generateText(model, prompt: "Hello, world!")
print(response.text)
```

### With Real Provider

```swift
import AIKit
import Foundation

// Get API key from environment
guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
    fatalError("Please set OPENAI_API_KEY environment variable")
}

// Create provider and model
let provider = OpenAIProvider(apiKey: apiKey)
let model = provider.languageModel("gpt-3.5-turbo")
let client = AIKit.client()

// Generate text
do {
    let response = try await client.generateText(
        model,
        prompt: "Explain what 'Hello, World!' means in programming"
    )
    print(response.text)
} catch {
    print("Error: \\(error)")
}
```

## Configuration Examples

### Temperature Variations

```swift
let provider = OpenAIProvider(apiKey: apiKey)
let client = AIKit.client()

// Conservative (deterministic)
let conservativeModel = provider.languageModel("gpt-4").temperature(0.1)
let conservativeResponse = try await client.generateText(
    conservativeModel,
    prompt: "What is 2 + 2?"
)

// Balanced
let balancedModel = provider.languageModel("gpt-4").temperature(0.7)
let balancedResponse = try await client.generateText(
    balancedModel,
    prompt: "Write a short poem about coding"
)

// Creative
let creativeModel = provider.languageModel("gpt-4").temperature(0.9)
let creativeResponse = try await client.generateText(
    creativeModel,
    prompt: "Invent a new programming language concept"
)

print("Conservative: \\(conservativeResponse.text)")
print("Balanced: \\(balancedResponse.text)")
print("Creative: \\(creativeResponse.text)")
```

### Token Limits

```swift
let model = provider.languageModel("gpt-4")

// Short response
let shortModel = model.maxTokens(50)
let shortResponse = try await client.generateText(
    shortModel,
    prompt: "Explain Swift in one sentence"
)

// Medium response
let mediumModel = model.maxTokens(200)
let mediumResponse = try await client.generateText(
    mediumModel,
    prompt: "Explain Swift concurrency"
)

// Long response
let longModel = model.maxTokens(500)
let longResponse = try await client.generateText(
    longModel,
    prompt: "Write a detailed guide to Swift optionals"
)
```

### Stop Sequences

```swift
let model = provider.languageModel("gpt-4")
    .stopSequences(["END", "FINISHED", "---"])

let response = try await client.generateText(
    model,
    prompt: "List 3 Swift features and then write END"
)

// Response will stop when it encounters "END", "FINISHED", or "---"
print(response.text)
```

## Message Conversations

### Simple Conversation

```swift
let messages = [
    Message.system("You are a helpful Swift programming assistant"),
    Message.user("How do I create an array in Swift?"),
    Message.assistant("You can create an array in Swift like this: var numbers = [1, 2, 3]"),
    Message.user("How do I add an element to it?")
]

let response = try await client.generateText(model, messages: messages)
print(response.text)
```

### Building Conversation History

```swift
var conversation: [Message] = [
    Message.system("You are a helpful coding tutor")
]

func askQuestion(_ question: String) async throws -> String {
    // Add user message
    conversation.append(Message.user(question))
    
    // Get AI response
    let response = try await client.generateText(model, messages: conversation)
    
    // Add AI response to conversation
    conversation.append(Message.assistant(response.text))
    
    return response.text
}

// Usage
let answer1 = try await askQuestion("What is a struct in Swift?")
print("AI: \\(answer1)")

let answer2 = try await askQuestion("How is it different from a class?")
print("AI: \\(answer2)")

let answer3 = try await askQuestion("Can you give me an example?")
print("AI: \\(answer3)")
```

### Conversation with Context

```swift
func createContextualConversation() -> [Message] {
    return [
        Message.system(\"\"\"
        You are an expert iOS developer helping with a weather app project.
        The app needs to display current weather and 5-day forecast.
        Focus on practical Swift/iOS solutions.
        \"\"\"),
        Message.user("I'm building a weather app. What architecture should I use?"),
        Message.assistant(\"\"\"
        For a weather app, I'd recommend MVVM architecture with the following structure:
        
        - Models: Weather, Forecast, Location
        - ViewModels: WeatherViewModel, ForecastViewModel
        - Views: SwiftUI views or UIKit view controllers
        - Services: WeatherService for API calls
        - Repository pattern for data management
        
        This keeps your code organized and testable.
        \"\"\"),
        Message.user("How should I handle the network requests?")
    ]
}

let contextualMessages = createContextualConversation()
let response = try await client.generateText(model, messages: contextualMessages)
```

## Error Handling

### Basic Error Handling

```swift
func generateTextSafely(prompt: String) async {
    do {
        let response = try await client.generateText(model, prompt: prompt)
        print("Success: \\(response.text)")
    } catch AIError.invalidModel(let message) {
        print("Invalid model error: \\(message)")
    } catch AIError.rateLimitExceeded(let retryAfter) {
        print("Rate limit exceeded. Retry after \\(retryAfter) seconds")
    } catch AIError.contentFiltered(let reason) {
        print("Content was filtered: \\(reason)")
    } catch {
        print("Unexpected error: \\(error.localizedDescription)")
    }
}

await generateTextSafely(prompt: "Hello, world!")
```

### Retry with Exponential Backoff

```swift
func generateTextWithRetry(
    prompt: String,
    maxRetries: Int = 3
) async throws -> TextResponse {
    var lastError: Error?
    
    for attempt in 0..<maxRetries {
        do {
            return try await client.generateText(model, prompt: prompt)
        } catch AIError.rateLimitExceeded(let retryAfter) {
            lastError = AIError.rateLimitExceeded(retryAfter)
            
            // Exponential backoff with jitter
            let baseDelay = pow(2.0, Double(attempt))
            let jitter = Double.random(in: 0...1)
            let delay = min(baseDelay + jitter + retryAfter, 60.0)
            
            print("Rate limited. Retrying in \\(delay) seconds...")
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch {
            lastError = error
            break // Don't retry for other errors
        }
    }
    
    throw lastError ?? AIError.maxRetriesExceeded
}

// Usage
do {
    let response = try await generateTextWithRetry(prompt: "Hello!")
    print(response.text)
} catch {
    print("Failed after retries: \\(error)")
}
```

### Graceful Degradation

```swift
func generateTextWithFallback(prompt: String) async -> String {
    // Try primary model first
    do {
        let primaryModel = provider.languageModel("gpt-4")
        let response = try await client.generateText(primaryModel, prompt: prompt)
        return response.text
    } catch {
        print("Primary model failed: \\(error). Trying fallback...")
    }
    
    // Fallback to cheaper model
    do {
        let fallbackModel = provider.languageModel("gpt-3.5-turbo")
        let response = try await client.generateText(fallbackModel, prompt: prompt)
        return "⚠️ [Fallback Response] \\(response.text)"
    } catch {
        print("Fallback model failed: \\(error). Using default response...")
    }
    
    // Final fallback
    return "I'm sorry, I'm unable to process your request at the moment. Please try again later."
}

// Usage
let result = await generateTextWithFallback(prompt: "Explain Swift optionals")
print(result)
```

## Streaming Examples

### Basic Streaming

```swift
func streamExample() async throws {
    let stream = client.streamText(
        model,
        prompt: "Write a story about a programmer learning Swift"
    )
    
    print("Streaming response:")
    for try await chunk in stream {
        print(chunk.delta, terminator: "")
        
        if let finishReason = chunk.finishReason {
            print("\\n\\nFinished: \\(finishReason)")
        }
    }
}

try await streamExample()
```

### Streaming with Progress Tracking

```swift
func streamWithProgress() async throws {
    let stream = client.streamText(
        model.maxTokens(500),
        prompt: "Write a comprehensive guide to Swift functions"
    )
    
    var totalText = ""
    var chunkCount = 0
    let startTime = Date()
    
    for try await chunk in stream {
        totalText += chunk.delta
        chunkCount += 1
        
        // Show progress every 10 chunks
        if chunkCount % 10 == 0 {
            let elapsed = Date().timeIntervalSince(startTime)
            print("\\n[Progress: \\(totalText.count) chars, \\(chunkCount) chunks, \\(elapsed:.1f)s]\\n")
        }
        
        print(chunk.delta, terminator: "")
        
        if let usage = chunk.usage {
            print("\\n\\nTokens used: \\(usage.totalTokens)")
        }
    }
}
```

### Streaming to UI (SwiftUI)

```swift
import SwiftUI

struct StreamingExample: View {
    @State private var streamedText = ""
    @State private var isStreaming = false
    
    let client = AIKit.client()
    let model: LanguageModel
    
    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                Text(streamedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .border(Color.gray)
            
            Button(isStreaming ? "Streaming..." : "Start Stream") {
                Task { await startStreaming() }
            }
            .disabled(isStreaming)
        }
        .padding()
    }
    
    private func startStreaming() async {
        isStreaming = true
        streamedText = ""
        
        do {
            let stream = client.streamText(
                model,
                prompt: "Explain Swift concurrency features in detail"
            )
            
            for try await chunk in stream {
                await MainActor.run {
                    streamedText += chunk.delta
                }
            }
        } catch {
            await MainActor.run {
                streamedText = "Error: \\(error.localizedDescription)"
            }
        }
        
        isStreaming = false
    }
}
```

## Object Generation

### Simple Object Generation

```swift
struct Recipe: Codable {
    let name: String
    let ingredients: [String]
    let instructions: [String]
    let cookingTime: Int
}

let schema = ObjectSchema<Recipe>()
let response = try await client.generateObject(
    model,
    prompt: "Create a recipe for chocolate chip cookies",
    schema: schema
)

let recipe = response.object
print("Recipe: \\(recipe.name)")
print("Ingredients: \\(recipe.ingredients.joined(separator: ", "))")
print("Cooking time: \\(recipe.cookingTime) minutes")
```

### Complex Object with Validation

```swift
struct UserProfile: Codable {
    let name: String
    let age: Int
    let email: String
    let preferences: [String]
    
    // Custom validation
    func validate() throws {
        guard age >= 0 && age <= 150 else {
            throw ValidationError.invalidAge
        }
        
        guard email.contains("@") else {
            throw ValidationError.invalidEmail
        }
    }
}

enum ValidationError: Error {
    case invalidAge
    case invalidEmail
}

func generateValidatedProfile(prompt: String) async throws -> UserProfile {
    let schema = ObjectSchema<UserProfile>()
    let response = try await client.generateObject(
        model,
        prompt: prompt,
        schema: schema
    )
    
    try response.object.validate()
    return response.object
}

// Usage
do {
    let profile = try await generateValidatedProfile(
        prompt: "Create a user profile for a 25-year-old software developer named Alex"
    )
    print("Generated profile: \\(profile)")
} catch {
    print("Validation failed: \\(error)")
}
```

### Array of Objects

```swift
struct Task: Codable {
    let title: String
    let priority: String
    let estimatedHours: Int
    let tags: [String]
}

let schema = ObjectSchema<[Task]>()
let response = try await client.generateObject(
    model,
    prompt: "Create a list of 5 programming tasks for a Swift project",
    schema: schema
)

let tasks = response.object
for (index, task) in tasks.enumerated() {
    print("\\(index + 1). \\(task.title) (\\(task.priority) priority, \\(task.estimatedHours)h)")
    print("   Tags: \\(task.tags.joined(separator: ", "))")
}
```

## Practical Applications

### Code Review Assistant

```swift
func reviewCode(_ code: String) async throws -> String {
    let prompt = \"\"\"
    Please review the following Swift code and provide feedback on:
    1. Code quality and best practices
    2. Potential bugs or issues
    3. Performance considerations
    4. Suggestions for improvement
    
    Code to review:
    ```swift
    \\(code)
    ```
    
    Provide constructive feedback:
    \"\"\"
    
    let model = provider.languageModel("gpt-4")
        .temperature(0.3) // More focused for code review
        .maxTokens(800)
    
    let response = try await client.generateText(model, prompt: prompt)
    return response.text
}

// Usage
let codeToReview = \"\"\"
func calculateTotal(items: [Double]) -> Double {
    var total = 0.0
    for item in items {
        total = total + item
    }
    return total
}
\"\"\"

let review = try await reviewCode(codeToReview)
print("Code Review:\\n\\(review)")
```

### Documentation Generator

```swift
func generateDocumentation(for functionSignature: String) async throws -> String {
    let prompt = \"\"\"
    Generate comprehensive documentation for this Swift function:
    
    \\(functionSignature)
    
    Include:
    - Brief description
    - Parameter descriptions
    - Return value description
    - Usage example
    - Any important notes or considerations
    
    Format as Swift documentation comments:
    \"\"\"
    
    let model = provider.languageModel("gpt-4")
        .temperature(0.4)
        .maxTokens(600)
    
    let response = try await client.generateText(model, prompt: prompt)
    return response.text
}

// Usage
let functionSignature = "func processUserData(_ users: [User], filter: (User) -> Bool) async throws -> [ProcessedUser]"
let documentation = try await generateDocumentation(for: functionSignature)
print(documentation)
```

### Unit Test Generator

```swift
func generateUnitTests(for code: String, functionName: String) async throws -> String {
    let prompt = \"\"\"
    Generate comprehensive XCTest unit tests for this Swift function:
    
    ```swift
    \\(code)
    ```
    
    Create tests that cover:
    - Normal operation with valid inputs
    - Edge cases (empty inputs, boundary values)
    - Error conditions
    - Different input variations
    
    Use XCTest framework and follow Swift testing best practices.
    Test class should be named \\(functionName)Tests.
    \"\"\"
    
    let model = provider.languageModel("gpt-4")
        .temperature(0.2) // More deterministic for code generation
        .maxTokens(1000)
    
    let response = try await client.generateText(model, prompt: prompt)
    return response.text
}

// Usage
let functionCode = \"\"\"
func isPalindrome(_ text: String) -> Bool {
    let cleanText = text.lowercased().filter { $0.isLetter }
    return cleanText == String(cleanText.reversed())
}
\"\"\"

let tests = try await generateUnitTests(for: functionCode, functionName: "isPalindrome")
print(tests)
```

## Next Steps

Explore more advanced examples:
- [Advanced Patterns](advanced-patterns.md) - Complex use cases and patterns
- [Provider Examples](provider-examples.md) - Provider-specific examples
- [Real-world Applications](real-world.md) - Production-ready examples