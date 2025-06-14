import Foundation

// MARK: - Core Provider Protocol

/// Main entry point for AI operations. Providers manage model creation and middleware.
public protocol AIProvider: Sendable {
    /// Human-readable name of the provider
    var name: String { get }
    
    /// Set of model IDs supported by this provider
    var supportedModels: Set<String> { get }
    
    /// Initialize provider with API key and middleware stack
    init(apiKey: String, middleware: [any AIMiddleware])
    
    /// Create a configured language model instance
    @available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
    func model(_ modelId: String, configuration: ModelConfiguration) throws -> LanguageModel
    
    /// Validate that the given configuration is supported
    func validateConfiguration(_ configuration: ModelConfiguration) throws
}

// MARK: - Language Model Protocol

/// Primary interface for AI model operations
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public protocol LanguageModel: Sendable {
    /// The provider that created this model
    var provider: any AIProvider { get }
    
    /// The model identifier
    var modelId: String { get }
    
    /// Current configuration
    var configuration: ModelConfiguration { get }
    
    // MARK: - Core Operations
    
    /// Generate text response
    func generateText(_ request: TextGenerationRequest) async throws -> TextGenerationResponse
    
    /// Stream text response
    func streamText(_ request: TextGenerationRequest) -> AsyncThrowingStream<TextChunk, Error>
    
    /// Generate structured object
    func generateObject<T: Codable>(_ request: ObjectGenerationRequest<T>) async throws -> ObjectGenerationResponse<T>
    
    /// Stream structured object
    func streamObject<T: Codable>(_ request: ObjectGenerationRequest<T>) -> AsyncThrowingStream<ObjectChunk<T>, Error>
    
    /// Generate embeddings
    func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResponse
    
    /// Generate multiple embeddings in batch
    func embedMany(_ request: BatchEmbeddingRequest) async throws -> BatchEmbeddingResponse
}

// MARK: - Model Configuration

/// Configuration for model behavior and parameters
public struct ModelConfiguration: Sendable {
    public let temperature: Double?
    public let maxTokens: Int?
    public let topP: Double?
    public let topK: Int?
    public let frequencyPenalty: Double?
    public let presencePenalty: Double?
    public let stopSequences: [String]?
    public let seed: Int?
    
    public init(
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        frequencyPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        stopSequences: [String]? = nil,
        seed: Int? = nil
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.topK = topK
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.stopSequences = stopSequences
        self.seed = seed
    }
}

// MARK: - Configuration Builder Extensions

public extension ModelConfiguration {
    func temperature(_ value: Double) -> ModelConfiguration {
        ModelConfiguration(
            temperature: value,
            maxTokens: maxTokens,
            topP: topP,
            topK: topK,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty,
            stopSequences: stopSequences,
            seed: seed
        )
    }
    
    func maxTokens(_ value: Int) -> ModelConfiguration {
        ModelConfiguration(
            temperature: temperature,
            maxTokens: value,
            topP: topP,
            topK: topK,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty,
            stopSequences: stopSequences,
            seed: seed
        )
    }
    
    func topP(_ value: Double) -> ModelConfiguration {
        ModelConfiguration(
            temperature: temperature,
            maxTokens: maxTokens,
            topP: value,
            topK: topK,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty,
            stopSequences: stopSequences,
            seed: seed
        )
    }
    
    func stopSequences(_ value: [String]) -> ModelConfiguration {
        ModelConfiguration(
            temperature: temperature,
            maxTokens: maxTokens,
            topP: topP,
            topK: topK,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty,
            stopSequences: value,
            seed: seed
        )
    }
}