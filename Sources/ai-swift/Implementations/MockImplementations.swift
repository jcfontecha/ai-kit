import Foundation

// MARK: - Mock Provider Implementation

/// Mock provider for testing and development
public struct MockProvider: AIProvider {
    public let name = "Mock Provider"
    public let supportedModels: Set<String> = ["mock-model-1", "mock-model-2"]
    
    private let apiKey: String
    private let middleware: [any AIMiddleware]
    
    public init(apiKey: String, middleware: [any AIMiddleware] = []) {
        self.apiKey = apiKey
        self.middleware = middleware
    }
    
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    public func model(_ modelId: String, configuration: ModelConfiguration = ModelConfiguration()) throws -> LanguageModel {
        guard supportedModels.contains(modelId) else {
            throw AIProviderError.unsupportedModel(modelId)
        }
        
        return MockLanguageModel(
            provider: self,
            modelId: modelId,
            configuration: configuration
        )
    }
    
    public func validateConfiguration(_ configuration: ModelConfiguration) throws {
        // Mock validation - always passes
    }
}

// MARK: - Mock Language Model Implementation

/// Mock language model for testing and development
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public struct MockLanguageModel: LanguageModel {
    public let provider: any AIProvider
    public let modelId: String
    public let configuration: ModelConfiguration
    
    public init(provider: any AIProvider, modelId: String, configuration: ModelConfiguration) {
        self.provider = provider
        self.modelId = modelId
        self.configuration = configuration
    }
    
    public func generateText(_ request: TextGenerationRequest) async throws -> TextGenerationResponse {
        // Mock implementation without Task.sleep to avoid availability issues
        
        let responseText = "Mock response to: \(request.messages.last?.content.first?.textValue ?? "unknown")"
        
        return TextGenerationResponse(
            text: responseText,
            finishReason: .stop,
            usage: TokenUsage(promptTokens: 10, completionTokens: 20, totalTokens: 30),
            messages: request.messages + [.assistant(responseText)],
            modelId: modelId
        )
    }
    
    public func streamText(_ request: TextGenerationRequest) -> AsyncThrowingStream<TextChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let responseText = "Mock streaming response to: \(request.messages.last?.content.first?.textValue ?? "unknown")"
                let words = responseText.split(separator: " ")
                
                var currentText = ""
                
                for (index, word) in words.enumerated() {
                    let delta = (index == 0 ? "" : " ") + String(word)
                    currentText += delta
                    
                    let chunk = TextChunk(
                        delta: delta,
                        snapshot: currentText,
                        finishReason: index == words.count - 1 ? .stop : nil,
                        usage: index == words.count - 1 ? TokenUsage(promptTokens: 10, completionTokens: 20, totalTokens: 30) : nil
                    )
                    
                    continuation.yield(chunk)
                    
                    // Mock implementation without delay
                }
                
                continuation.finish()
            }
        }
    }
    
    public func generateObject<T: Codable>(_ request: ObjectGenerationRequest<T>) async throws -> ObjectGenerationResponse<T> {
        fatalError("MockLanguageModel.generateObject not implemented")
    }
    
    public func streamObject<T: Codable>(_ request: ObjectGenerationRequest<T>) -> AsyncThrowingStream<ObjectChunk<T>, Error> {
        fatalError("MockLanguageModel.streamObject not implemented")
    }
    
    public func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResponse {
        // Mock implementation without delay
        
        // Generate mock embedding vector
        let dimensions = 384 // Mock embedding size
        let embedding = (0..<dimensions).map { _ in Float.random(in: -1...1) }
        
        return EmbeddingResponse(
            embedding: embedding,
            usage: TokenUsage(promptTokens: 5, completionTokens: 0, totalTokens: 5),
            modelId: modelId
        )
    }
    
    public func embedMany(_ request: BatchEmbeddingRequest) async throws -> BatchEmbeddingResponse {
        // Mock implementation without delay
        
        // Generate mock embeddings for each input
        let dimensions = 384
        let embeddings = request.values.map { _ in
            (0..<dimensions).map { _ in Float.random(in: -1...1) }
        }
        
        return BatchEmbeddingResponse(
            embeddings: embeddings,
            usage: TokenUsage(
                promptTokens: request.values.count * 5,
                completionTokens: 0,
                totalTokens: request.values.count * 5
            ),
            modelId: modelId
        )
    }
}

// MARK: - Mock Schema Validator

/// Mock schema validator for testing
public struct MockSchemaValidator: SchemaValidator {
    public init() {}
    
    public func validate(_ data: Data, against schema: JSONSchema) throws -> ValidationResult {
        // Mock validation - always passes
        return ValidationResult(isValid: true)
    }
    
    public func validatePartial(_ partialJSON: String, against schema: JSONSchema) throws -> PartialValidationResult {
        // Mock partial validation
        let isComplete = partialJSON.hasSuffix("}")
        return PartialValidationResult(
            isValidSoFar: true,
            canContinue: !isComplete,
            suggestions: isComplete ? [] : [
                CompletionSuggestion(type: .closeBrace, suggestion: "}")
            ]
        )
    }
}

// MARK: - Protocol Conformances for Request/Response Types

extension TextGenerationRequest: AIRequest {
    public var requestId: String { UUID().uuidString }
    public var timestamp: Date { Date() }
}

extension ObjectGenerationRequest: AIRequest {
    public var requestId: String { UUID().uuidString }
    public var timestamp: Date { Date() }
}

extension EmbeddingRequest: AIRequest {
    public var requestId: String { UUID().uuidString }
    public var timestamp: Date { Date() }
}

extension BatchEmbeddingRequest: AIRequest {
    public var requestId: String { UUID().uuidString }
    public var timestamp: Date { Date() }
}

extension TextGenerationResponse: AIResponse {}

extension ObjectGenerationResponse: AIResponse {}

extension EmbeddingResponse: AIResponse {}

extension BatchEmbeddingResponse: AIResponse {}

extension TextChunk: StreamChunk {}

extension ObjectChunk: StreamChunk {}

// MARK: - Mock Rate Limiter

/// Mock rate limiter for testing
public actor MockRateLimiter: RateLimiter {
    private var requestCount = 0
    private let maxRequests: Int
    private let resetInterval: TimeInterval
    private var lastReset: Date = Date()
    
    public init(maxRequests: Int = 100, resetInterval: TimeInterval = 60) {
        self.maxRequests = maxRequests
        self.resetInterval = resetInterval
    }
    
    public func checkLimit() async throws {
        let now = Date()
        
        // Reset counter if interval has passed
        if now.timeIntervalSince(lastReset) >= resetInterval {
            requestCount = 0
            lastReset = now
        }
        
        // Check if limit exceeded
        if requestCount >= maxRequests {
            throw RateLimitError(retryAfter: resetInterval - now.timeIntervalSince(lastReset))
        }
        
        requestCount += 1
    }
}