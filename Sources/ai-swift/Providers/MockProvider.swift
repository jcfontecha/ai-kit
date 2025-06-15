import Foundation

// MARK: - Mock Provider Implementation

/// Mock provider for testing and development.
///
/// `MockProvider` is a complete implementation of the `AIProvider` protocol that
/// provides realistic mock responses without making actual API calls. It's designed
/// for testing, development, and demonstration purposes.
///
/// ## Features
/// - Realistic mock responses with configurable behavior
/// - Streaming support with simulated delays
/// - Tool calling simulation
/// - Usage information tracking
/// - Error simulation capabilities
/// - Support for all standard model parameters
///
/// ## Usage Examples
///
/// ### Basic Usage
/// ```swift
/// let provider = MockProvider(apiKey: "mock-key")
/// let model = provider.languageModel("mock-gpt-4")
/// let client = AIClient()
/// 
/// let response = try await client.generateText(model, prompt: "Hello!")
/// print(response.text) // "Mock response to: Hello!"
/// ```
///
/// ### With Configuration
/// ```swift
/// let model = provider.languageModel("mock-claude")
///     .temperature(0.8)
///     .maxTokens(150)
/// 
/// let response = try await client.generateText(model, prompt: "Write a story")
/// ```
///
/// ### Streaming
/// ```swift
/// let stream = client.streamText(model, prompt: "Count to 10")
/// for try await chunk in stream {
///     print(chunk.delta, terminator: "")
/// }
/// ```
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct MockProvider: AIProvider {
    
    // MARK: - Properties
    
    /// Provider name for identification and logging.
    public let name = "Mock Provider"
    
    /// Mock API key (not used for actual authentication).
    private let apiKey: String
    
    /// Configuration for mock behavior.
    private let configuration: MockConfiguration
    
    // MARK: - Initialization
    
    /// Creates a new mock provider with the specified API key and configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Mock API key (any string is accepted)
    ///   - configuration: Configuration for mock behavior
    public init(apiKey: String = "mock-api-key", configuration: MockConfiguration = .default) {
        self.apiKey = apiKey
        self.configuration = configuration
    }
    
    // MARK: - AIProvider Implementation
    
    /// Create a configured language model instance.
    ///
    /// The mock provider accepts any model ID and creates a working model instance.
    /// Common mock model IDs include "mock-gpt-4", "mock-claude-3", etc.
    ///
    /// - Parameter modelId: Any model identifier
    /// - Returns: A configured LanguageModel ready for use
    public func languageModel(_ modelId: String) -> LanguageModel {
        return LanguageModel(provider: self, modelId: modelId)
    }
    
    /// Execute raw text generation with mock responses.
    ///
    /// Generates realistic mock responses based on the input prompt and configuration.
    /// The response includes simulated token usage and respects configuration parameters.
    ///
    /// - Parameter request: The provider request to process
    /// - Returns: A mock response with generated content
    /// - Throws: Simulated errors based on configuration
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        // Simulate API delay if configured
        if let delay = configuration.responseDelay {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        // Check for simulated errors
        if let errorRate = configuration.errorRate, Double.random(in: 0...1) < errorRate {
            throw AIProviderError.serviceUnavailable("Simulated error for testing")
        }
        
        // Generate mock response based on the last user message
        let userMessage = request.messages.last { $0.role == .user }
        let prompt = userMessage?.content.first?.textValue ?? "unknown input"
        
        let responseText = generateMockResponse(for: prompt, configuration: request.configuration)
        let usage = generateMockUsage(prompt: prompt, response: responseText)
        
        return ProviderResponse(
            content: responseText,
            usage: usage,
            finishReason: .stop,
            providerMetadata: [
                "mock_provider": "true",
                "model_id": request.modelId,
                "prompt_length": "\(prompt.count)"
            ]
        )
    }
    
    /// Execute raw streaming text generation with mock chunks.
    ///
    /// Provides realistic streaming simulation with configurable chunk sizes and delays.
    /// Useful for testing streaming UI components and error handling.
    ///
    /// - Parameter request: The provider request to process
    /// - Returns: AsyncThrowingStream of mock response chunks
    public func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Simulate API delay
                    if let delay = configuration.responseDelay {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    
                    // Check for simulated errors
                    if let errorRate = configuration.errorRate, Double.random(in: 0...1) < errorRate {
                        throw AIProviderError.serviceUnavailable("Simulated streaming error")
                    }
                    
                    // Generate mock response
                    let userMessage = request.messages.last { $0.role == .user }
                    let prompt = userMessage?.content.first?.textValue ?? "unknown input"
                    let responseText = generateMockResponse(for: prompt, configuration: request.configuration)
                    
                    // Split response into words for streaming
                    let words = responseText.split(separator: " ")
                    
                    for (index, word) in words.enumerated() {
                        // Add space before word (except first)
                        let delta = (index == 0 ? "" : " ") + String(word)
                        
                        let chunk = ProviderChunk(
                            delta: delta,
                            usage: index == words.count - 1 ? generateMockUsage(prompt: prompt, response: responseText) : nil,
                            finishReason: index == words.count - 1 ? .stop : nil,
                            chunkIndex: index
                        )
                        
                        continuation.yield(chunk)
                        
                        // Simulate streaming delay between chunks
                        if let chunkDelay = configuration.chunkDelay {
                            try await Task.sleep(nanoseconds: UInt64(chunkDelay * 1_000_000_000))
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Validate configuration parameters (mock implementation).
    ///
    /// The mock provider accepts all configuration parameters but can be configured
    /// to simulate validation errors for testing purposes.
    ///
    /// - Parameter configuration: Configuration to validate
    /// - Throws: Simulated validation errors if configured
    public func validateConfiguration(_ configuration: ModelConfiguration) throws {
        // Mock validation - can be configured to throw errors for testing
        if self.configuration.strictValidation {
            if let temp = configuration.temperature, temp > 2.0 {
                throw AIProviderError.unsupportedParameter("temperature", "Mock provider supports max 2.0")
            }
            if let maxTokens = configuration.maxTokens, maxTokens > 4000 {
                throw AIProviderError.unsupportedParameter("maxTokens", "Mock provider supports max 4000 tokens")
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Generate a mock response based on the input prompt.
    private func generateMockResponse(for prompt: String, configuration: ModelConfiguration) -> String {
        // Generate contextual responses based on prompt content
        let lowercasePrompt = prompt.lowercased()
        
        if lowercasePrompt.contains("weather") {
            return "I don't have access to real-time weather data in this mock environment, but I can help you understand how to get weather information."
        } else if lowercasePrompt.contains("calculate") || lowercasePrompt.contains("math") {
            return "I can help with calculations! For example, 2 + 2 = 4. What specific calculation would you like me to help with?"
        } else if lowercasePrompt.contains("story") || lowercasePrompt.contains("write") {
            return "Once upon a time, in a world where AI assistants learned to dream, there was a helpful assistant who loved to create stories and help humans with their creative endeavors."
        } else if lowercasePrompt.contains("hello") || lowercasePrompt.contains("hi") {
            return "Hello! I'm a mock AI assistant. I'm here to help demonstrate the capabilities of the Swift AI SDK."
        } else if lowercasePrompt.contains("explain") {
            return "I'd be happy to explain that topic! In this mock environment, I can provide general explanations and demonstrate how AI responses would work."
        } else {
            // Default response with prompt echo
            return "Mock response to: \(prompt)"
        }
    }
    
    /// Generate realistic mock usage information.
    private func generateMockUsage(prompt: String, response: String) -> Usage {
        // Simulate realistic token counts (roughly 1 token per 4 characters)
        let promptTokens = max(1, prompt.count / 4)
        let completionTokens = max(1, response.count / 4)
        
        return Usage(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            promptCost: Double(promptTokens) * 0.00001, // $0.01 per 1K tokens
            completionCost: Double(completionTokens) * 0.00002, // $0.02 per 1K tokens
            currency: "USD"
        )
    }
}

// MARK: - Extended Provider Implementation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension MockProvider: ExtendedAIProvider {
    
    /// Mock provider capabilities.
    public var capabilities: ProviderCapabilities {
        return ProviderCapabilities(
            supportedModels: Set([
                "mock-gpt-4", "mock-gpt-3.5", "mock-claude-3", "mock-claude-2",
                "mock-llama-2", "mock-gemini", "mock-test-model"
            ]),
            supportsStreaming: true,
            supportsTools: configuration.supportsTools,
            supportsObjectGeneration: configuration.supportsObjectGeneration,
            supportsImageInputs: configuration.supportsImageInputs,
            supportsEmbeddings: false,
            supportedParameters: Set([
                "temperature", "maxTokens", "topP", "topK",
                "frequencyPenalty", "presencePenalty", "stopSequences", "seed"
            ]),
            maxTokens: 4000,
            maxContextLength: 8000
        )
    }
    
    /// Get mock model information.
    public func modelInfo(_ modelId: String) throws -> ModelInfo {
        // Return mock model info based on model ID
        let contextLength: Int
        let maxOutputTokens: Int
        let name: String
        let description: String
        
        if modelId.contains("gpt-4") {
            name = "Mock GPT-4"
            description = "Mock version of GPT-4 for testing and development"
            contextLength = 8000
            maxOutputTokens = 4000
        } else if modelId.contains("claude") {
            name = "Mock Claude"
            description = "Mock version of Claude for testing and development"
            contextLength = 100000
            maxOutputTokens = 4000
        } else {
            name = "Mock Model"
            description = "Generic mock model for testing"
            contextLength = 4000
            maxOutputTokens = 2000
        }
        
        return ModelInfo(
            id: modelId,
            name: name,
            description: description,
            contextLength: contextLength,
            maxOutputTokens: maxOutputTokens,
            supportsTools: configuration.supportsTools,
            supportsImages: configuration.supportsImageInputs,
            knowledgeCutoff: Date(),
            pricing: ModelPricing(inputTokenCost: 0.00001, outputTokenCost: 0.00002)
        )
    }
    
    /// Check if a model is supported (all models are supported in mock).
    public func supportsModel(_ modelId: String) -> Bool {
        return true // Mock provider supports any model ID
    }
}

// MARK: - Mock Configuration

/// Configuration for mock provider behavior.
///
/// Allows customization of how the mock provider behaves, including
/// error simulation, delays, and feature support.
public struct MockConfiguration: Sendable {
    
    /// Delay before responding (in seconds).
    public let responseDelay: TimeInterval?
    
    /// Delay between streaming chunks (in seconds).
    public let chunkDelay: TimeInterval?
    
    /// Rate of simulated errors (0.0 to 1.0).
    public let errorRate: Double?
    
    /// Whether to perform strict validation.
    public let strictValidation: Bool
    
    /// Whether to simulate tool calling support.
    public let supportsTools: Bool
    
    /// Whether to simulate object generation support.
    public let supportsObjectGeneration: Bool
    
    /// Whether to simulate image input support.
    public let supportsImageInputs: Bool
    
    /// Maximum response length in characters.
    public let maxResponseLength: Int
    
    public init(
        responseDelay: TimeInterval? = nil,
        chunkDelay: TimeInterval? = nil,
        errorRate: Double? = nil,
        strictValidation: Bool = false,
        supportsTools: Bool = true,
        supportsObjectGeneration: Bool = true,
        supportsImageInputs: Bool = false,
        maxResponseLength: Int = 1000
    ) {
        self.responseDelay = responseDelay
        self.chunkDelay = chunkDelay
        self.errorRate = errorRate
        self.strictValidation = strictValidation
        self.supportsTools = supportsTools
        self.supportsObjectGeneration = supportsObjectGeneration
        self.supportsImageInputs = supportsImageInputs
        self.maxResponseLength = maxResponseLength
    }
    
    /// Default configuration with no delays or errors.
    public static let `default` = MockConfiguration()
    
    /// Configuration with realistic delays for testing.
    public static let realistic = MockConfiguration(
        responseDelay: 0.5,
        chunkDelay: 0.1
    )
    
    /// Configuration that simulates errors for testing error handling.
    public static let errorProne = MockConfiguration(
        errorRate: 0.1,
        strictValidation: true
    )
    
    /// Fast configuration with minimal delays.
    public static let fast = MockConfiguration(
        responseDelay: 0.01,
        chunkDelay: 0.001
    )
}