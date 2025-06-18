import Foundation

// MARK: - AIProvider Protocol

/// Protocol that handles the translation between AI SDK standard format and provider-specific APIs.
///
/// `AIProvider` serves as the translation layer in the Swift AI SDK architecture, following
/// patterns established by the Vercel AI SDK. It is responsible for converting standardized
/// requests into provider-specific API calls and translating responses back to the standard format.
///
/// ## Core Responsibilities
/// - **Model Factory**: Create `LanguageModel` instances for specific model IDs
/// - **Format Translation**: Convert between AI SDK standard formats and provider APIs
/// - **Settings Validation**: Validate and map configuration parameters to provider formats
/// - **HTTP Communication**: Handle all network communication with the AI service
/// - **Authentication**: Manage API keys and authentication headers
/// - **Error Translation**: Convert provider-specific errors to standard AI SDK errors
///
/// ## Architecture Position
/// ```
/// AIClient (Framework) → LanguageModel (Config) → AIProvider (Translation) → AI Service
/// ```
///
/// The provider acts as a translation layer between the framework and the actual AI service,
/// ensuring that the framework can work with multiple providers through a unified interface.
///
/// ## Implementation Guidelines
///
/// ### Provider-Specific Responsibilities
/// - Transform `ProviderRequest` to the provider's API format
/// - Make HTTP calls to the provider's endpoints
/// - Parse provider responses to `ProviderResponse` format
/// - Handle provider-specific errors and rate limits
/// - Validate model IDs and configuration parameters
///
/// ### Framework Responsibilities (Handled by AIClient)
/// - Apply middleware chains
/// - JSON schema validation for object generation
/// - Tool execution orchestration
/// - High-level error handling and retries
/// - Streaming management and chunk processing
///
/// ## Usage Examples
///
/// ### Basic Provider Implementation
/// ```swift
/// public struct OpenAIProvider: AIProvider {
///     public let name = "OpenAI"
///     private let apiKey: String
///     
///     public func languageModel(_ modelId: String) -> LanguageModel {
///         return LanguageModel(provider: self, modelId: modelId)
///     }
///     
///     public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
///         // Transform to OpenAI format, make HTTP call, parse response
///     }
/// }
/// ```
///
/// ### Provider with Validation
/// ```swift
/// public func validateConfiguration(_ configuration: ModelConfiguration) throws {
///     if let temp = configuration.temperature, temp > 2.0 {
///         throw AIProviderError.unsupportedParameter("temperature", "OpenAI supports max 2.0")
///     }
/// }
/// ```
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol AIProvider: Sendable {
    
    // MARK: - Provider Identity
    
    /// Human-readable name of the provider.
    ///
    /// This should be a consistent identifier for the provider, such as "OpenAI",
    /// "Anthropic", "Google", etc. Used for logging, debugging, and provider comparison.
    var name: String { get }
    
    // MARK: - Model Factory
    
    /// Create a configured language model instance.
    ///
    /// This factory method creates a `LanguageModel` that encapsulates the provider,
    /// model ID, and default configuration. The returned model can be further
    /// configured using the builder pattern methods.
    ///
    /// - Parameter modelId: The specific model identifier (e.g., "gpt-4", "claude-3-sonnet")
    /// - Returns: A `LanguageModel` instance ready for use with `AIClient`
    ///
    /// ## Example
    /// ```swift
    /// let model = provider.languageModel("gpt-4")
    /// let configuredModel = model.temperature(0.8).maxTokens(150)
    /// ```
    func languageModel(_ modelId: String) -> LanguageModel
    
    // MARK: - Raw Generation Methods
    
    /// Execute raw text generation with provider-specific format translation.
    ///
    /// This method handles the complete pipeline for a single text generation request:
    /// 1. Transform the standard `ProviderRequest` to the provider's API format
    /// 2. Validate the request parameters against provider capabilities
    /// 3. Make the HTTP request to the provider's API
    /// 4. Parse the provider's response format
    /// 5. Transform the response to the standard `ProviderResponse` format
    ///
    /// - Parameter request: The standardized request containing messages, configuration, and tools
    /// - Returns: A `ProviderResponse` with the generated content and metadata
    /// - Throws: Provider-specific errors that will be handled by the framework
    ///
    /// ## Implementation Notes
    /// - Handle provider-specific authentication (API keys, headers)
    /// - Map configuration parameters to provider equivalents
    /// - Convert message formats to provider schemas
    /// - Parse usage information and finish reasons
    /// - Handle rate limiting and provider-specific errors
    func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse
    
    /// Execute raw streaming text generation with provider-specific format translation.
    ///
    /// This method provides real-time streaming of text generation:
    /// 1. Transform the standard `ProviderRequest` to the provider's streaming format
    /// 2. Establish a streaming connection to the provider's API
    /// 3. Parse incremental responses as they arrive
    /// 4. Transform each chunk to the standard `ProviderChunk` format
    /// 5. Handle stream completion and error conditions
    ///
    /// - Parameter request: The standardized request for streaming generation
    /// - Returns: AsyncThrowingStream of `ProviderChunk` objects
    ///
    /// ## Implementation Notes
    /// - Handle Server-Sent Events (SSE) or similar streaming protocols
    /// - Parse partial JSON responses and tool calls
    /// - Manage connection lifecycle and error recovery
    /// - Ensure proper resource cleanup on cancellation
    func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error>
    
    // MARK: - Transcription Methods
    
    /// Create a configured transcription model instance.
    ///
    /// This factory method creates a `TranscriptionModel` that encapsulates the provider,
    /// model ID, and default configuration. The returned model can be further
    /// configured using the builder pattern methods.
    ///
    /// - Parameter modelId: The specific transcription model identifier (e.g., "whisper-1", "nova-2")
    /// - Returns: A `TranscriptionModel` instance ready for use with `AIClient`
    ///
    /// ## Example
    /// ```swift
    /// let model = provider.transcriptionModel("whisper-1")
    /// let configuredModel = model.language("en").temperature(0.2)
    /// ```
    func transcriptionModel(_ modelId: String) -> TranscriptionModel
    
    /// Execute raw transcription with provider-specific format translation.
    ///
    /// This method handles the complete pipeline for a transcription request:
    /// 1. Transform the standard `TranscriptionProviderRequest` to the provider's API format
    /// 2. Validate the request parameters against provider capabilities
    /// 3. Make the HTTP request to the provider's transcription API
    /// 4. Parse the provider's response format
    /// 5. Transform the response to the standard `TranscriptionProviderResponse` format
    ///
    /// - Parameter request: The standardized transcription request containing audio and configuration
    /// - Returns: A `TranscriptionProviderResponse` with the transcribed text and metadata
    /// - Throws: Provider-specific errors that will be handled by the framework
    ///
    /// ## Implementation Notes
    /// - Handle provider-specific authentication (API keys, headers)
    /// - Map configuration parameters to provider equivalents
    /// - Convert audio input formats to provider schemas
    /// - Parse transcription results and timing information
    /// - Handle rate limiting and provider-specific errors
    func transcribeRaw(_ request: TranscriptionProviderRequest) async throws -> TranscriptionProviderResponse
    
    // MARK: - Provider Capabilities
    
    /// Provider capabilities for mode support
    var supportedGenerationModes: Set<GenerationMode> { get }
    
    /// Default generation mode for this provider
    var defaultGenerationMode: GenerationMode { get }
    
    // MARK: - Validation
    
    /// Validate that the given configuration is supported by this provider.
    ///
    /// This method allows providers to validate configuration parameters before
    /// they are used in generation requests. It should check parameter ranges,
    /// supported features, and any provider-specific constraints.
    ///
    /// - Parameter configuration: The configuration to validate
    /// - Throws: `AIProviderError` if the configuration is invalid or unsupported
    ///
    /// ## Example Implementation
    /// ```swift
    /// func validateConfiguration(_ configuration: ModelConfiguration) throws {
    ///     if let temp = configuration.temperature, temp > 2.0 {
    ///         throw AIProviderError.unsupportedParameter("temperature", "Max value is 2.0")
    ///     }
    ///     if let topK = configuration.topK {
    ///         throw AIProviderError.unsupportedParameter("topK", "Not supported by this provider")
    ///     }
    /// }
    /// ```
    func validateConfiguration(_ configuration: ModelConfiguration) throws
}

// MARK: - Default Implementations

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension AIProvider {
    
    /// Default validation implementation that accepts all configurations.
    ///
    /// Providers can override this to implement specific validation logic.
    /// The default implementation performs no validation and accepts all parameters.
    func validateConfiguration(_ configuration: ModelConfiguration) throws {
        // Default implementation: accept all configurations
        // Providers should override this to implement specific validation
    }
    
    /// Default transcription model factory implementation.
    ///
    /// Providers should override this to create provider-specific transcription models.
    /// The default implementation creates a basic TranscriptionModel with this provider.
    func transcriptionModel(_ modelId: String) -> TranscriptionModel {
        return TranscriptionModel(provider: self, modelId: modelId)
    }
    
    /// Default transcription implementation that throws an unsupported error.
    ///
    /// Providers must override this method to implement actual transcription functionality.
    /// The default implementation throws an error indicating transcription is not supported.
    func transcribeRaw(_ request: TranscriptionProviderRequest) async throws -> TranscriptionProviderResponse {
        throw AIProviderError.unsupportedParameter(
            "transcription",
            "Provider '\(name)' does not support transcription"
        )
    }
}

// MARK: - Provider Error Types

/// Errors specific to AI provider operations.
///
/// These errors represent issues that occur at the provider translation layer,
/// such as unsupported parameters, authentication failures, or API-specific errors.
public enum AIProviderError: Error, Sendable {
    
    /// The specified model ID is not supported by this provider.
    case unsupportedModel(String)
    
    /// A configuration parameter is not supported or has an invalid value.
    case unsupportedParameter(String, String)
    
    /// Authentication failed (invalid API key, expired token, etc.).
    case authenticationFailed(String)
    
    /// Rate limit exceeded for the provider.
    case rateLimitExceeded(retryAfter: TimeInterval?)
    
    /// The provider's API returned an unexpected response format.
    case invalidResponse(String)
    
    /// Network or connectivity issues.
    case networkError(Error)
    
    /// The provider's service is temporarily unavailable.
    case serviceUnavailable(String)
    
    /// A provider-specific error that doesn't fit other categories.
    case providerSpecific(String, underlyingError: Error?)
}

// MARK: - Provider Error Extensions

extension AIProviderError: LocalizedError {
    
    /// Localized description of the provider error.
    public var errorDescription: String? {
        switch self {
        case .unsupportedModel(let modelId):
            return "Model '\(modelId)' is not supported by this provider"
        case .unsupportedParameter(let param, let reason):
            return "Parameter '\(param)' is not supported: \(reason)"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .rateLimitExceeded(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limit exceeded. Retry after \(retryAfter) seconds"
            } else {
                return "Rate limit exceeded"
            }
        case .invalidResponse(let reason):
            return "Invalid response from provider: \(reason)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serviceUnavailable(let reason):
            return "Service unavailable: \(reason)"
        case .providerSpecific(let message, _):
            return message
        }
    }
}

// MARK: - Provider Capabilities

/// Describes the capabilities of an AI provider.
///
/// This structure can be used to query what features and parameters
/// a provider supports, enabling dynamic feature detection and UI adaptation.
public struct ProviderCapabilities: Sendable {
    
    /// Models supported by this provider.
    public let supportedModels: Set<String>
    
    /// Whether the provider supports streaming responses.
    public let supportsStreaming: Bool
    
    /// Whether the provider supports tool/function calling.
    public let supportsTools: Bool
    
    /// Whether the provider supports structured object generation.
    public let supportsObjectGeneration: Bool
    
    /// Whether the provider supports image inputs.
    public let supportsImageInputs: Bool
    
    /// Whether the provider supports embedding generation.
    public let supportsEmbeddings: Bool
    
    /// Whether the provider supports audio transcription.
    public let supportsTranscription: Bool
    
    /// Configuration parameters supported by this provider.
    public let supportedParameters: Set<String>
    
    /// Maximum tokens supported by this provider.
    public let maxTokens: Int?
    
    /// Maximum context length supported by this provider.
    public let maxContextLength: Int?
    
    public init(
        supportedModels: Set<String> = [],
        supportsStreaming: Bool = true,
        supportsTools: Bool = false,
        supportsObjectGeneration: Bool = false,
        supportsImageInputs: Bool = false,
        supportsEmbeddings: Bool = false,
        supportsTranscription: Bool = false,
        supportedParameters: Set<String> = [],
        maxTokens: Int? = nil,
        maxContextLength: Int? = nil
    ) {
        self.supportedModels = supportedModels
        self.supportsStreaming = supportsStreaming
        self.supportsTools = supportsTools
        self.supportsObjectGeneration = supportsObjectGeneration
        self.supportsImageInputs = supportsImageInputs
        self.supportsEmbeddings = supportsEmbeddings
        self.supportsTranscription = supportsTranscription
        self.supportedParameters = supportedParameters
        self.maxTokens = maxTokens
        self.maxContextLength = maxContextLength
    }
}

// MARK: - Extended Provider Protocol

/// Extended provider protocol for advanced capabilities.
///
/// Providers can optionally implement this protocol to expose additional
/// capabilities and metadata.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol ExtendedAIProvider: AIProvider {
    
    /// The capabilities of this provider.
    var capabilities: ProviderCapabilities { get }
    
    /// Get detailed information about a specific model.
    func modelInfo(_ modelId: String) throws -> ModelInfo
    
    /// Check if a specific model ID is supported.
    func supportsModel(_ modelId: String) -> Bool
}

// MARK: - Model Information

/// Detailed information about a specific model.
public struct ModelInfo: Sendable {
    
    /// The model identifier.
    public let id: String
    
    /// Human-readable name of the model.
    public let name: String
    
    /// Description of the model's capabilities.
    public let description: String
    
    /// Maximum context length for this model.
    public let contextLength: Int
    
    /// Maximum output tokens for this model.
    public let maxOutputTokens: Int
    
    /// Whether this model supports function calling.
    public let supportsTools: Bool
    
    /// Whether this model supports image inputs.
    public let supportsImages: Bool
    
    /// The model's training data cutoff date.
    public let knowledgeCutoff: Date?
    
    /// Pricing information (tokens per dollar, etc.).
    public let pricing: ModelPricing?
    
    public init(
        id: String,
        name: String,
        description: String,
        contextLength: Int,
        maxOutputTokens: Int,
        supportsTools: Bool = false,
        supportsImages: Bool = false,
        knowledgeCutoff: Date? = nil,
        pricing: ModelPricing? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.contextLength = contextLength
        self.maxOutputTokens = maxOutputTokens
        self.supportsTools = supportsTools
        self.supportsImages = supportsImages
        self.knowledgeCutoff = knowledgeCutoff
        self.pricing = pricing
    }
}

// MARK: - Model Pricing

/// Pricing information for a model.
public struct ModelPricing: Sendable {
    
    /// Cost per input token (in dollars).
    public let inputTokenCost: Double
    
    /// Cost per output token (in dollars).
    public let outputTokenCost: Double
    
    /// Currency for the pricing.
    public let currency: String
    
    public init(inputTokenCost: Double, outputTokenCost: Double, currency: String = "USD") {
        self.inputTokenCost = inputTokenCost
        self.outputTokenCost = outputTokenCost
        self.currency = currency
    }
}