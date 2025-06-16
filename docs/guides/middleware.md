# Middleware

This guide covers AIKit's middleware system for transforming requests and responses.

## Overview

Middleware in AIKit allows you to:
- Transform requests before they reach the provider
- Modify responses before they return to your application  
- Add logging, authentication, rate limiting, caching, and more
- Chain multiple middleware for complex processing pipelines

## Middleware Protocol

```swift
public protocol Middleware {
    var priority: Int { get }
    
    func processRequest(_ request: ProviderRequest) async throws -> ProviderRequest
    func processResponse(_ response: ProviderResponse) async throws -> ProviderResponse
    func processStreamChunk(_ chunk: ProviderChunk) async throws -> ProviderChunk
}
```

## Creating Middleware

### Basic Middleware

```swift
struct LoggingMiddleware: Middleware {
    let priority = 100 // Higher priority = runs earlier
    
    func processRequest(_ request: ProviderRequest) async throws -> ProviderRequest {
        print("🔵 Request: \\(request.modelId) - \\(request.messages.count) messages")
        return request
    }
    
    func processResponse(_ response: ProviderResponse) async throws -> ProviderResponse {
        print("🟢 Response: \\(response.text.count) characters, \\(response.usage.totalTokens) tokens")
        return response
    }
    
    func processStreamChunk(_ chunk: ProviderChunk) async throws -> ProviderChunk {
        if !chunk.delta.isEmpty {
            print("📦 Chunk: \\(chunk.delta.count) characters")
        }
        return chunk
    }
}
```

### Request Transformation Middleware

```swift
struct PromptEnhancementMiddleware: Middleware {
    let priority = 200
    
    func processRequest(_ request: ProviderRequest) async throws -> ProviderRequest {
        var modifiedRequest = request
        
        // Add system message if none exists
        if !request.messages.contains(where: { $0.role == .system }) {
            let systemMessage = Message.system("You are a helpful and accurate assistant.")
            modifiedRequest.messages.insert(systemMessage, at: 0)
        }
        
        // Enhance user messages with context
        modifiedRequest.messages = request.messages.map { message in
            if message.role == .user {
                let enhancedContent = \"\"\"
                Context: Please provide clear, accurate, and helpful responses.
                
                User request: \\(message.content)
                \"\"\"
                return Message(role: .user, content: enhancedContent)
            }
            return message
        }
        
        return modifiedRequest
    }
    
    func processResponse(_ response: ProviderResponse) async throws -> ProviderResponse {
        return response
    }
    
    func processStreamChunk(_ chunk: ProviderChunk) async throws -> ProviderChunk {
        return chunk
    }
}
```

### Response Processing Middleware

```swift
struct ContentFilterMiddleware: Middleware {
    let priority = 50
    
    private let bannedWords = ["spam", "scam", "malware"]
    
    func processRequest(_ request: ProviderRequest) async throws -> ProviderRequest {
        return request
    }
    
    func processResponse(_ response: ProviderResponse) async throws -> ProviderResponse {
        let filteredText = filterContent(response.text)
        
        if filteredText != response.text {
            var modifiedResponse = response
            modifiedResponse.text = filteredText
            modifiedResponse.metadata["content_filtered"] = true
            return modifiedResponse
        }
        
        return response
    }
    
    func processStreamChunk(_ chunk: ProviderChunk) async throws -> ProviderChunk {
        let filteredDelta = filterContent(chunk.delta)
        
        if filteredDelta != chunk.delta {
            var modifiedChunk = chunk
            modifiedChunk.delta = filteredDelta
            modifiedChunk.metadata["content_filtered"] = true
            return modifiedChunk
        }
        
        return chunk
    }
    
    private func filterContent(_ text: String) -> String {
        var filteredText = text
        for word in bannedWords {
            filteredText = filteredText.replacingOccurrences(
                of: word,
                with: "***",
                options: .caseInsensitive
            )
        }
        return filteredText
    }
}
```

## Built-in Middleware

AIKit provides several built-in middleware:

### Logging Middleware

```swift
let client = AIKit.client(middleware: [
    AIKit.loggingMiddleware()
])

// With custom configuration
let client = AIKit.client(middleware: [
    AIKit.loggingMiddleware(
        level: .debug,
        includeTokens: true,
        includeTimings: true
    )
])
```

### Rate Limiting Middleware

```swift
let client = AIKit.client(middleware: [
    AIKit.rateLimitMiddleware(
        maxRequests: 100,
        timeWindow: 60 // seconds
    )
])
```

### Retry Middleware

```swift
let client = AIKit.client(middleware: [
    AIKit.retryMiddleware(
        maxRetries: 3,
        backoffStrategy: .exponential,
        retryableErrors: [.networkError, .rateLimitExceeded]
    )
])
```

### Caching Middleware

```swift
let client = AIKit.client(middleware: [
    AIKit.cachingMiddleware(
        maxCacheSize: 100,
        ttl: 3600 // 1 hour
    )
])
```

## Advanced Middleware Examples

### Authentication Middleware

```swift
struct AuthenticationMiddleware: Middleware {
    let priority = 1000 // High priority
    
    private let tokenProvider: () async throws -> String
    
    init(tokenProvider: @escaping () async throws -> String) {
        self.tokenProvider = tokenProvider
    }
    
    func processRequest(_ request: ProviderRequest) async throws -> ProviderRequest {
        let token = try await tokenProvider()
        
        var modifiedRequest = request
        modifiedRequest.metadata["authorization"] = "Bearer \\(token)"
        
        return modifiedRequest
    }
    
    func processResponse(_ response: ProviderResponse) async throws -> ProviderResponse {
        return response
    }
    
    func processStreamChunk(_ chunk: ProviderChunk) async throws -> ProviderChunk {
        return chunk
    }
}

// Usage
let authMiddleware = AuthenticationMiddleware {
    // Fetch fresh token
    return try await getAuthToken()
}

let client = AIKit.client(middleware: [authMiddleware])
```

### Metrics Collection Middleware

```swift
struct MetricsMiddleware: Middleware {
    let priority = 10
    
    private let metricsCollector: MetricsCollector
    
    init(metricsCollector: MetricsCollector) {
        self.metricsCollector = metricsCollector
    }
    
    func processRequest(_ request: ProviderRequest) async throws -> ProviderRequest {
        await metricsCollector.recordRequest(
            model: request.modelId,
            messageCount: request.messages.count,
            timestamp: Date()
        )
        
        return request
    }
    
    func processResponse(_ response: ProviderResponse) async throws -> ProviderResponse {
        await metricsCollector.recordResponse(
            tokens: response.usage.totalTokens,
            latency: response.metadata["latency"] as? TimeInterval ?? 0,
            finishReason: response.finishReason
        )
        
        return response
    }
    
    func processStreamChunk(_ chunk: ProviderChunk) async throws -> ProviderChunk {
        if let usage = chunk.usage {
            await metricsCollector.recordStreamingTokens(usage.totalTokens)
        }
        
        return chunk
    }
}
```

### Error Handling Middleware

```swift
struct ErrorHandlingMiddleware: Middleware {
    let priority = 0 // Low priority, runs last for requests
    
    private let errorReporter: ErrorReporter
    
    func processRequest(_ request: ProviderRequest) async throws -> ProviderRequest {
        return request
    }
    
    func processResponse(_ response: ProviderResponse) async throws -> ProviderResponse {
        // Log successful responses
        await errorReporter.recordSuccess(
            model: response.metadata["model"] as? String ?? "unknown"
        )
        
        return response
    }
    
    func processStreamChunk(_ chunk: ProviderChunk) async throws -> ProviderChunk {
        return chunk
    }
}

// Custom error reporting
protocol ErrorReporter {
    func recordSuccess(model: String) async
    func recordError(_ error: Error, context: [String: Any]) async
}
```

### Cost Tracking Middleware

```swift
struct CostTrackingMiddleware: Middleware {
    let priority = 20
    
    private let costCalculator: CostCalculator
    private let budgetManager: BudgetManager
    
    func processRequest(_ request: ProviderRequest) async throws -> ProviderRequest {
        // Check budget before request
        let estimatedCost = costCalculator.estimateCost(
            model: request.modelId,
            inputTokens: estimateInputTokens(request.messages)
        )
        
        try await budgetManager.checkBudget(estimatedCost)
        
        return request
    }
    
    func processResponse(_ response: ProviderResponse) async throws -> ProviderResponse {
        // Track actual cost
        let actualCost = costCalculator.calculateCost(
            model: response.metadata["model"] as? String ?? "unknown",
            usage: response.usage
        )
        
        await budgetManager.recordCost(actualCost)
        
        var modifiedResponse = response
        modifiedResponse.metadata["cost"] = actualCost
        
        return modifiedResponse
    }
    
    func processStreamChunk(_ chunk: ProviderChunk) async throws -> ProviderChunk {
        return chunk
    }
    
    private func estimateInputTokens(_ messages: [Message]) -> Int {
        // Rough estimation: 4 characters per token
        return messages.map { $0.content.count / 4 }.reduce(0, +)
    }
}
```

## Middleware Composition

### Chaining Multiple Middleware

```swift
let client = AIKit.client(middleware: [
    // High priority - runs first for requests, last for responses
    AuthenticationMiddleware(tokenProvider: getToken),
    
    // Medium priority - core functionality
    LoggingMiddleware(),
    RateLimitingMiddleware(maxRequests: 100),
    CostTrackingMiddleware(calculator: costCalc, budget: budgetMgr),
    
    // Low priority - final processing
    ContentFilterMiddleware(),
    MetricsMiddleware(collector: metrics)
])
```

### Conditional Middleware

```swift
struct ConditionalMiddleware: Middleware {
    let priority = 100
    
    private let condition: (ProviderRequest) -> Bool
    private let innerMiddleware: Middleware
    
    init(
        condition: @escaping (ProviderRequest) -> Bool,
        middleware: Middleware
    ) {
        self.condition = condition
        self.innerMiddleware = middleware
    }
    
    func processRequest(_ request: ProviderRequest) async throws -> ProviderRequest {
        if condition(request) {
            return try await innerMiddleware.processRequest(request)
        }
        return request
    }
    
    func processResponse(_ response: ProviderResponse) async throws -> ProviderResponse {
        // Condition based on original request context
        return try await innerMiddleware.processResponse(response)
    }
    
    func processStreamChunk(_ chunk: ProviderChunk) async throws -> ProviderChunk {
        return try await innerMiddleware.processStreamChunk(chunk)
    }
}

// Usage: Only apply caching for expensive models
let conditionalCaching = ConditionalMiddleware(
    condition: { request in
        ["gpt-4", "claude-3-opus"].contains(request.modelId)
    },
    middleware: CachingMiddleware()
)
```

## Error Handling in Middleware

### Handling Middleware Errors

```swift
struct RobustMiddleware: Middleware {
    let priority = 100
    
    func processRequest(_ request: ProviderRequest) async throws -> ProviderRequest {
        do {
            return try await performRequestProcessing(request)
        } catch {
            // Log error but don't fail the request
            logger.error("Middleware processing failed: \\(error)")
            return request
        }
    }
    
    func processResponse(_ response: ProviderResponse) async throws -> ProviderResponse {
        do {
            return try await performResponseProcessing(response)
        } catch {
            logger.error("Response processing failed: \\(error)")
            // Return original response on error
            return response
        }
    }
    
    func processStreamChunk(_ chunk: ProviderChunk) async throws -> ProviderChunk {
        do {
            return try await performChunkProcessing(chunk)
        } catch {
            logger.error("Chunk processing failed: \\(error)")
            return chunk
        }
    }
}
```

### Circuit Breaker Middleware

```swift
actor CircuitBreaker {
    enum State {
        case closed, open, halfOpen
    }
    
    private var state: State = .closed
    private var failureCount = 0
    private var lastFailureTime: Date?
    
    private let failureThreshold: Int
    private let timeout: TimeInterval
    
    init(failureThreshold: Int = 5, timeout: TimeInterval = 60) {
        self.failureThreshold = failureThreshold
        self.timeout = timeout
    }
    
    func canExecute() -> Bool {
        switch state {
        case .closed:
            return true
        case .open:
            guard let lastFailure = lastFailureTime else { return true }
            if Date().timeIntervalSince(lastFailure) > timeout {
                state = .halfOpen
                return true
            }
            return false
        case .halfOpen:
            return true
        }
    }
    
    func recordSuccess() {
        failureCount = 0
        state = .closed
    }
    
    func recordFailure() {
        failureCount += 1
        lastFailureTime = Date()
        
        if failureCount >= failureThreshold {
            state = .open
        }
    }
}

struct CircuitBreakerMiddleware: Middleware {
    let priority = 150
    private let circuitBreaker = CircuitBreaker()
    
    func processRequest(_ request: ProviderRequest) async throws -> ProviderRequest {
        guard await circuitBreaker.canExecute() else {
            throw AIError.serviceUnavailable("Circuit breaker is open")
        }
        
        return request
    }
    
    func processResponse(_ response: ProviderResponse) async throws -> ProviderResponse {
        await circuitBreaker.recordSuccess()
        return response
    }
    
    func processStreamChunk(_ chunk: ProviderChunk) async throws -> ProviderChunk {
        // Record success when stream completes successfully
        if chunk.finishReason != nil {
            await circuitBreaker.recordSuccess()
        }
        return chunk
    }
}
```

## Testing Middleware

### Unit Testing

```swift
import XCTest
@testable import AIKit

class MiddlewareTests: XCTestCase {
    func testLoggingMiddleware() async throws {
        let middleware = LoggingMiddleware()
        
        let request = ProviderRequest(
            modelId: "test-model",
            messages: [Message.user("Hello")],
            configuration: ModelConfiguration()
        )
        
        let processedRequest = try await middleware.processRequest(request)
        
        // Verify request is unchanged
        XCTAssertEqual(processedRequest.modelId, request.modelId)
        XCTAssertEqual(processedRequest.messages.count, request.messages.count)
    }
    
    func testContentFilterMiddleware() async throws {
        let middleware = ContentFilterMiddleware()
        
        let response = ProviderResponse(
            text: "This contains spam content",
            finishReason: .stop,
            usage: Usage(promptTokens: 10, completionTokens: 20, totalTokens: 30),
            metadata: [:]
        )
        
        let filteredResponse = try await middleware.processResponse(response)
        
        XCTAssertEqual(filteredResponse.text, "This contains *** content")
        XCTAssertEqual(filteredResponse.metadata["content_filtered"] as? Bool, true)
    }
}
```

### Integration Testing

```swift
class MiddlewareIntegrationTests: XCTestCase {
    func testMiddlewareChain() async throws {
        let middleware = [
            LoggingMiddleware(),
            ContentFilterMiddleware(),
            MetricsMiddleware(collector: TestMetricsCollector())
        ]
        
        let client = AIKit.client(middleware: middleware)
        let provider = MockProvider()
        let model = provider.languageModel("test-model")
        
        let response = try await client.generateText(
            model,
            prompt: "Test message with spam content"
        )
        
        // Verify middleware chain processed the response
        XCTAssertTrue(response.text.contains("***"))
    }
}
```

## Best Practices

### 1. Set Appropriate Priorities

```swift
// ✅ Good: Logical priority ordering
let middleware = [
    AuthenticationMiddleware(),      // Priority: 1000 (first)
    RateLimitingMiddleware(),       // Priority: 500
    LoggingMiddleware(),            // Priority: 100
    ContentFilterMiddleware()       // Priority: 50 (last)
]
```

### 2. Handle Errors Gracefully

```swift
// ✅ Good: Graceful error handling
func processRequest(_ request: ProviderRequest) async throws -> ProviderRequest {
    do {
        return try await enhanceRequest(request)
    } catch {
        logger.warning("Request enhancement failed, using original: \\(error)")
        return request // Fallback to original
    }
}

// ❌ Avoid: Letting middleware errors break the chain
func processRequest(_ request: ProviderRequest) async throws -> ProviderRequest {
    return try await enhanceRequest(request) // May throw and break the chain
}
```

### 3. Keep Middleware Focused

```swift
// ✅ Good: Single responsibility
struct LoggingMiddleware: Middleware {
    // Only handles logging
}

struct AuthenticationMiddleware: Middleware {
    // Only handles authentication
}

// ❌ Avoid: Middleware doing too much
struct MonolithicMiddleware: Middleware {
    // Handles logging, auth, rate limiting, caching, etc.
}
```

### 4. Make Middleware Configurable

```swift
// ✅ Good: Configurable middleware
struct LoggingMiddleware: Middleware {
    let level: LogLevel
    let includeTokens: Bool
    let includeTimings: Bool
    
    init(
        level: LogLevel = .info,
        includeTokens: Bool = false,
        includeTimings: Bool = false
    ) {
        self.level = level
        self.includeTokens = includeTokens
        self.includeTimings = includeTimings
    }
}
```

## See Also

- [AIClient](../api-reference/ai-client.md) - Client configuration with middleware
- [Error Handling](error-handling.md) - Error handling patterns
- [Testing](testing.md) - Testing strategies for middleware
- [Examples](../examples/middleware-examples.md) - Real-world middleware examples