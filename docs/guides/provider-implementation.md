# Provider Implementation Guide

This guide shows how to create custom AI providers for AIKit, allowing you to integrate with any AI service.

## Overview

Providers in AIKit translate between the standard AIKit interface and specific AI service APIs. They implement the `AIProvider` protocol and handle:

- Model configuration
- Request/response transformation
- API communication
- Error handling
- Streaming support

## AIProvider Protocol

```swift
public protocol AIProvider {
    var name: String { get }
    var capabilities: ProviderCapabilities { get }
    
    func languageModel(_ modelId: String) -> LanguageModel
    func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse
    func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error>
}
```

## Basic Provider Implementation

### Simple Provider Structure

```swift
import Foundation
import AIKit

public struct CustomProvider: AIProvider {
    public let name = "CustomProvider"
    
    // API configuration
    private let apiKey: String
    private let baseURL: URL
    
    public init(apiKey: String, baseURL: String = "https://api.custom-ai.com") {
        self.apiKey = apiKey
        self.baseURL = URL(string: baseURL)!
    }
    
    public var capabilities: ProviderCapabilities {
        ProviderCapabilities(
            streaming: true,
            toolCalling: true,
            objectGeneration: true,
            vision: false,
            imageGeneration: false
        )
    }
    
    public func languageModel(_ modelId: String) -> LanguageModel {
        return LanguageModel(provider: self, modelId: modelId)
    }
}
```

### Implementing generateTextRaw

```swift
extension CustomProvider {
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        // 1. Transform AIKit request to provider format
        let apiRequest = try transformRequest(request)
        
        // 2. Make HTTP request
        let httpResponse = try await makeHTTPRequest(apiRequest)
        
        // 3. Transform provider response to AIKit format
        let providerResponse = try transformResponse(httpResponse)
        
        return providerResponse
    }
    
    private func transformRequest(_ request: ProviderRequest) throws -> CustomAPIRequest {
        // Convert messages
        let messages = request.messages.map { message in
            CustomAPIMessage(
                role: transformRole(message.role),
                content: message.content
            )
        }
        
        return CustomAPIRequest(
            model: request.modelId,
            messages: messages,
            temperature: request.configuration.temperature,
            max_tokens: request.configuration.maxTokens,
            top_p: request.configuration.topP,
            frequency_penalty: request.configuration.frequencyPenalty,
            presence_penalty: request.configuration.presencePenalty,
            stop: request.configuration.stopSequences.isEmpty ? nil : request.configuration.stopSequences
        )
    }
    
    private func transformRole(_ role: Message.Role) -> String {
        switch role {
        case .system: return "system"
        case .user: return "user"
        case .assistant: return "assistant"
        case .tool: return "tool"
        }
    }
    
    private func makeHTTPRequest(_ request: CustomAPIRequest) async throws -> CustomAPIResponse {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("/chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \\(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Encode request
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)
        
        // Make request
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.networkError(URLError(.badServerResponse))
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw try handleHTTPError(statusCode: httpResponse.statusCode, data: data)
        }
        
        // Decode response
        let decoder = JSONDecoder()
        return try decoder.decode(CustomAPIResponse.self, from: data)
    }
    
    private func transformResponse(_ apiResponse: CustomAPIResponse) throws -> ProviderResponse {
        guard let choice = apiResponse.choices.first else {
            throw AIError.noContentGenerated
        }
        
        return ProviderResponse(
            text: choice.message.content ?? "",
            finishReason: transformFinishReason(choice.finish_reason),
            usage: Usage(
                promptTokens: apiResponse.usage.prompt_tokens,
                completionTokens: apiResponse.usage.completion_tokens,
                totalTokens: apiResponse.usage.total_tokens
            ),
            metadata: [
                "model": apiResponse.model,
                "id": apiResponse.id,
                "created": apiResponse.created
            ]
        )
    }
    
    private func transformFinishReason(_ reason: String?) -> FinishReason {
        switch reason {
        case "stop": return .stop
        case "length": return .length
        case "content_filter": return .contentFilter
        case "tool_calls": return .toolCalls
        default: return .stop
        }
    }
}
```

## API Data Structures

Define the provider's API format:

```swift
// Request structures
struct CustomAPIRequest: Codable {
    let model: String
    let messages: [CustomAPIMessage]
    let temperature: Double?
    let max_tokens: Int?
    let top_p: Double?
    let frequency_penalty: Double?
    let presence_penalty: Double?
    let stop: [String]?
    let stream: Bool?
}

struct CustomAPIMessage: Codable {
    let role: String
    let content: String
}

// Response structures
struct CustomAPIResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [CustomAPIChoice]
    let usage: CustomAPIUsage
}

struct CustomAPIChoice: Codable {
    let index: Int
    let message: CustomAPIMessage
    let finish_reason: String?
}

struct CustomAPIUsage: Codable {
    let prompt_tokens: Int
    let completion_tokens: Int
    let total_tokens: Int
}
```

## Streaming Implementation

### Basic Streaming

```swift
extension CustomProvider {
    public func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Create streaming request
                    var streamRequest = try transformRequest(request)
                    streamRequest.stream = true
                    
                    // Make streaming HTTP request
                    let stream = try await makeStreamingRequest(streamRequest)
                    
                    // Process stream
                    for try await chunk in stream {
                        let providerChunk = try transformStreamChunk(chunk)
                        continuation.yield(providerChunk)
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func makeStreamingRequest(_ request: CustomAPIRequest) async throws -> AsyncThrowingStream<String, Error> {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("/chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \\(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/plain", forHTTPHeaderField: "Accept")
        
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          200...299 ~= httpResponse.statusCode else {
                        throw AIError.networkError(URLError(.badServerResponse))
                    }
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))
                            if data != "[DONE]" {
                                continuation.yield(data)
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func transformStreamChunk(_ jsonString: String) throws -> ProviderChunk {
        let data = jsonString.data(using: .utf8)!
        let streamResponse = try JSONDecoder().decode(CustomStreamResponse.self, from: data)
        
        guard let choice = streamResponse.choices.first else {
            throw AIError.invalidResponse("No choices in stream response")
        }
        
        return ProviderChunk(
            delta: choice.delta.content ?? "",
            finishReason: choice.finish_reason.map(transformFinishReason),
            usage: streamResponse.usage.map { usage in
                Usage(
                    promptTokens: usage.prompt_tokens,
                    completionTokens: usage.completion_tokens,
                    totalTokens: usage.total_tokens
                )
            }
        )
    }
}

// Streaming response structures
struct CustomStreamResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [CustomStreamChoice]
    let usage: CustomAPIUsage?
}

struct CustomStreamChoice: Codable {
    let index: Int
    let delta: CustomStreamDelta
    let finish_reason: String?
}

struct CustomStreamDelta: Codable {
    let content: String?
}
```

### Advanced Streaming with Buffering

```swift
extension CustomProvider {
    private func makeStreamingRequestWithBuffer(_ request: CustomAPIRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = try await makeStreamingRequest(request)
                    var buffer = StreamBuffer()
                    
                    for try await line in stream {
                        let chunks = try buffer.process(line)
                        for chunk in chunks {
                            let providerChunk = try transformStreamChunk(chunk)
                            continuation.yield(providerChunk)
                        }
                    }
                    
                    // Process any remaining buffer
                    let finalChunks = buffer.finalize()
                    for chunk in finalChunks {
                        if !chunk.isEmpty {
                            let providerChunk = try transformStreamChunk(chunk)
                            continuation.yield(providerChunk)
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

class StreamBuffer {
    private var buffer = ""
    
    func process(_ line: String) throws -> [String] {
        buffer += line + "\\n"
        
        var chunks: [String] = []
        let lines = buffer.components(separatedBy: "\\n")
        
        // Process all complete lines except the last (potentially incomplete) one
        for i in 0..<(lines.count - 1) {
            let line = lines[i]
            if line.hasPrefix("data: ") {
                let data = String(line.dropFirst(6))
                if data != "[DONE]" && !data.isEmpty {
                    chunks.append(data)
                }
            }
        }
        
        // Keep the last line in buffer
        buffer = lines.last ?? ""
        
        return chunks
    }
    
    func finalize() -> [String] {
        defer { buffer = "" }
        return buffer.isEmpty ? [] : [buffer]
    }
}
```

## Error Handling

### HTTP Error Handling

```swift
extension CustomProvider {
    private func handleHTTPError(statusCode: Int, data: Data) throws -> AIError {
        switch statusCode {
        case 400:
            return .invalidRequest(parseErrorMessage(data))
        case 401:
            return .authenticationFailed
        case 429:
            let retryAfter = parseRetryAfter(data)
            return .rateLimitExceeded(retryAfter)
        case 500...599:
            return .serverError(parseErrorMessage(data))
        default:
            return .networkError(URLError(.badServerResponse))
        }
    }
    
    private func parseErrorMessage(_ data: Data) -> String {
        struct ErrorResponse: Codable {
            let error: ErrorDetail
        }
        
        struct ErrorDetail: Codable {
            let message: String
            let type: String?
            let code: String?
        }
        
        do {
            let errorResponse = try JSONDecoder().decode(ErrorResponse.self, from: data)
            return errorResponse.error.message
        } catch {
            return "Unknown error"
        }
    }
    
    private func parseRetryAfter(_ data: Data) -> TimeInterval {
        struct RateLimitResponse: Codable {
            let error: RateLimitError
        }
        
        struct RateLimitError: Codable {
            let message: String
            let retry_after: Double?
        }
        
        do {
            let response = try JSONDecoder().decode(RateLimitResponse.self, from: data)
            return response.error.retry_after ?? 60.0
        } catch {
            return 60.0 // Default retry after 1 minute
        }
    }
}
```

### Network Error Handling

```swift
extension CustomProvider {
    private func handleNetworkError(_ error: Error) -> AIError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return .networkError(urlError)
            case .timedOut:
                return .timeoutError
            case .cancelled:
                return .requestCancelled
            default:
                return .networkError(urlError)
            }
        }
        
        return .unknownError(error)
    }
}
```

## Tool Calling Support

### Request Transformation with Tools

```swift
extension CustomProvider {
    private func transformRequestWithTools(_ request: ProviderRequest) throws -> CustomAPIRequest {
        var apiRequest = try transformRequest(request)
        
        // Add tools if present
        if !request.configuration.tools.isEmpty {
            apiRequest.tools = request.configuration.tools.map(transformTool)
            apiRequest.tool_choice = "auto"
        }
        
        return apiRequest
    }
    
    private func transformTool(_ tool: Tool) -> CustomAPITool {
        switch tool {
        case .function(let function):
            return CustomAPITool(
                type: "function",
                function: CustomAPIFunction(
                    name: function.name,
                    description: function.description,
                    parameters: function.parameters.jsonSchema
                )
            )
        }
    }
}

// Tool structures
struct CustomAPITool: Codable {
    let type: String
    let function: CustomAPIFunction
}

struct CustomAPIFunction: Codable {
    let name: String
    let description: String
    let parameters: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case name, description, parameters
    }
    
    init(name: String, description: String, parameters: [String: Any]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        
        // Handle dynamic JSON
        let parametersData = try container.decode(Data.self, forKey: .parameters)
        parameters = try JSONSerialization.jsonObject(with: parametersData) as? [String: Any] ?? [:]
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        
        let parametersData = try JSONSerialization.data(withJSONObject: parameters)
        try container.encode(parametersData, forKey: .parameters)
    }
}
```

## Object Generation Support

### Schema Handling

```swift
extension CustomProvider {
    public func generateObjectRaw<T: Codable>(
        _ request: ProviderRequest,
        schema: ObjectSchema<T>
    ) async throws -> ObjectResponse<T> {
        // Add JSON mode to request
        var modifiedRequest = request
        modifiedRequest.configuration.responseFormat = .json
        
        // Add schema instruction to prompt
        let schemaInstruction = generateSchemaInstruction(schema)
        modifiedRequest = addSchemaInstruction(modifiedRequest, instruction: schemaInstruction)
        
        // Generate text
        let response = try await generateTextRaw(modifiedRequest)
        
        // Parse JSON response
        let object = try parseObject(response.text, schema: schema)
        
        return ObjectResponse(
            object: object,
            finishReason: response.finishReason,
            usage: response.usage,
            rawText: response.text,
            metadata: response.metadata
        )
    }
    
    private func generateSchemaInstruction<T: Codable>(_ schema: ObjectSchema<T>) -> String {
        let jsonSchema = schema.jsonSchema
        return \"\"\"
        Please respond with a valid JSON object that matches this schema:
        \\(jsonSchema)
        
        Respond with only the JSON object, no additional text.
        \"\"\"
    }
    
    private func parseObject<T: Codable>(_ text: String, schema: ObjectSchema<T>) throws -> T {
        // Extract JSON from response (may contain additional text)
        let jsonText = try extractJSON(from: text)
        
        guard let data = jsonText.data(using: .utf8) else {
            throw AIError.invalidResponse("Could not encode JSON text")
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIError.jsonParseError(error, jsonText)
        }
    }
    
    private func extractJSON(from text: String) throws -> String {
        // Find JSON content between { and }
        guard let startIndex = text.firstIndex(of: "{"),
              let endIndex = text.lastIndex(of: "}") else {
            throw AIError.invalidResponse("No JSON object found in response")
        }
        
        return String(text[startIndex...endIndex])
    }
}
```

## Testing Your Provider

### Unit Tests

```swift
import XCTest
@testable import AIKit

class CustomProviderTests: XCTestCase {
    var provider: CustomProvider!
    
    override func setUp() {
        super.setUp()
        provider = CustomProvider(apiKey: "test-key")
    }
    
    func testBasicTextGeneration() async throws {
        let model = provider.languageModel("test-model")
        let client = AIKit.client()
        
        // This would require mocking the HTTP calls
        // or using a test API endpoint
        let response = try await client.generateText(
            model,
            prompt: "Hello, world!"
        )
        
        XCTAssertFalse(response.text.isEmpty)
    }
    
    func testStreamingGeneration() async throws {
        let model = provider.languageModel("test-model")
        let client = AIKit.client()
        
        let stream = client.streamText(model, prompt: "Count to 5")
        
        var chunks: [StreamChunk] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }
        
        XCTAssertFalse(chunks.isEmpty)
    }
    
    func testErrorHandling() async {
        // Test various error conditions
        let model = provider.languageModel("invalid-model")
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
class CustomProviderIntegrationTests: XCTestCase {
    func testRealAPICall() async throws {
        let apiKey = ProcessInfo.processInfo.environment["CUSTOM_API_KEY"]
        XCTSkipIf(apiKey?.isEmpty != false, "API key not provided")
        
        let provider = CustomProvider(apiKey: apiKey!)
        let model = provider.languageModel("your-model")
        let client = AIKit.client()
        
        let response = try await client.generateText(
            model,
            prompt: "Say hello in exactly 2 words"
        )
        
        XCTAssertFalse(response.text.isEmpty)
        let wordCount = response.text.split(separator: " ").count
        XCTAssertLessThanOrEqual(wordCount, 3) // Allow some tolerance
    }
}
```

## Advanced Features

### Caching Support

```swift
extension CustomProvider {
    private let cache = NSCache<NSString, CachedResponse>()
    
    private func cachedGenerateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        let cacheKey = generateCacheKey(request)
        
        if let cached = cache.object(forKey: cacheKey as NSString) {
            if !cached.isExpired {
                return cached.response
            }
        }
        
        let response = try await generateTextRaw(request)
        
        let cachedResponse = CachedResponse(
            response: response,
            expirationDate: Date().addingTimeInterval(3600) // 1 hour
        )
        cache.setObject(cachedResponse, forKey: cacheKey as NSString)
        
        return response
    }
    
    private func generateCacheKey(_ request: ProviderRequest) -> String {
        // Create hash from request parameters
        let prompt = request.messages.map { $0.content }.joined()
        let config = "\\(request.modelId)-\\(request.configuration.temperature)-\\(request.configuration.maxTokens ?? 0)"
        return "\\(prompt.hashValue)-\\(config.hashValue)"
    }
}

class CachedResponse {
    let response: ProviderResponse
    let expirationDate: Date
    
    var isExpired: Bool {
        Date() > expirationDate
    }
    
    init(response: ProviderResponse, expirationDate: Date) {
        self.response = response
        self.expirationDate = expirationDate
    }
}
```

### Rate Limiting

```swift
actor RateLimiter {
    private var requestTimes: [Date] = []
    private let maxRequests: Int
    private let timeWindow: TimeInterval
    
    init(maxRequests: Int, timeWindow: TimeInterval) {
        self.maxRequests = maxRequests
        self.timeWindow = timeWindow
    }
    
    func checkRateLimit() async throws {
        let now = Date()
        
        // Remove old requests outside time window
        requestTimes = requestTimes.filter { now.timeIntervalSince($0) < timeWindow }
        
        guard requestTimes.count < maxRequests else {
            let oldestRequest = requestTimes.first!
            let waitTime = timeWindow - now.timeIntervalSince(oldestRequest)
            throw AIError.rateLimitExceeded(waitTime)
        }
        
        requestTimes.append(now)
    }
}

extension CustomProvider {
    private static let rateLimiter = RateLimiter(maxRequests: 100, timeWindow: 60) // 100 requests per minute
    
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        try await Self.rateLimiter.checkRateLimit()
        return try await actualGenerateTextRaw(request)
    }
}
```

## Best Practices

### 1. Follow AIKit Patterns

```swift
// ✅ Good: Follow established patterns
public struct MyProvider: AIProvider {
    public let name = "MyProvider"
    public let capabilities = ProviderCapabilities(...)
    
    public func languageModel(_ modelId: String) -> LanguageModel {
        return LanguageModel(provider: self, modelId: modelId)
    }
}

// ❌ Avoid: Deviating from protocol requirements
public struct BadProvider: AIProvider {
    // Missing required properties/methods
}
```

### 2. Handle All Error Cases

```swift
// ✅ Good: Comprehensive error handling
private func handleResponse(_ data: Data, _ response: URLResponse) throws -> ProviderResponse {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw AIError.networkError(URLError(.badServerResponse))
    }
    
    switch httpResponse.statusCode {
    case 200...299:
        return try parseSuccessResponse(data)
    case 400:
        throw .invalidRequest(parseError(data))
    case 401:
        throw .authenticationFailed
    case 429:
        throw .rateLimitExceeded(parseRetryAfter(data))
    case 500...599:
        throw .serverError(parseError(data))
    default:
        throw .unknownError(HTTPError(statusCode: httpResponse.statusCode))
    }
}
```

### 3. Implement Proper Streaming

```swift
// ✅ Good: Proper streaming implementation
public func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
    return AsyncThrowingStream { continuation in
        Task {
            do {
                // Proper error handling and cleanup
                defer { /* cleanup */ }
                
                let stream = try await makeStreamingRequest(request)
                for try await chunk in stream {
                    continuation.yield(try transformChunk(chunk))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
```

### 4. Use Appropriate Data Types

```swift
// ✅ Good: Use proper types for API responses
struct APIResponse: Codable {
    let id: String
    let model: String
    let choices: [Choice]
    let usage: Usage
    let created: Date
    
    private enum CodingKeys: String, CodingKey {
        case id, model, choices, usage
        case created = "created_at"
    }
}

// ❌ Avoid: Using Any or loose typing
struct BadAPIResponse: Codable {
    let data: [String: Any] // Hard to work with
}
```

## See Also

- [AIProvider Protocol](../api-reference/ai-provider.md) - Full protocol reference
- [Provider Examples](../examples/provider-examples.md) - Real provider implementations  
- [Error Handling](error-handling.md) - Comprehensive error handling
- [Testing](testing.md) - Testing strategies for providers