import Foundation

// MARK: - LanguageModel

/// Pre-configured model instances that contain all the settings needed for execution.
///
/// `LanguageModel` represents a configured AI model ready for use with specific settings.
/// It acts as a configuration container that holds the provider, model identifier, and
/// all parameters needed for AI operations.
///
/// In the new architecture, `LanguageModel` is a simple struct that serves as a configuration
/// holder rather than an active protocol. The actual operations are performed by `AIClient`
/// using the configuration stored in the `LanguageModel`.
///
/// ## Key Properties
/// - **provider**: The `AIProvider` that handles the translation to the actual AI service
/// - **modelId**: The specific model identifier (e.g., "gpt-4", "claude-3-sonnet")
/// - **configuration**: Model parameters like temperature, max tokens, etc.
///
/// ## Usage Examples
///
/// ### Basic Model Creation
/// ```swift
/// let provider = OpenAIProvider(apiKey: "sk-...")
/// let model = provider.languageModel("gpt-4")
/// ```
///
/// ### Model with Configuration
/// ```swift
/// let model = provider.languageModel("gpt-4")
///     .temperature(0.8)
///     .maxTokens(150)
///     .topP(0.9)
/// ```
///
/// ### Using with AIClient
/// ```swift
/// let client = AIClient()
/// let response = try await client.generateText(model, prompt: "Hello")
/// ```
public struct LanguageModel: Sendable {
    
    // MARK: - Properties
    
    /// The provider that created this model and handles translation to the AI service
    public let provider: any AIProvider
    
    /// The model identifier (e.g., "gpt-4", "claude-3-sonnet", "llama-2-70b")
    public let modelId: String
    
    /// The configuration parameters for this model instance
    public let configuration: ModelConfiguration
    
    // MARK: - Initialization
    
    /// Creates a new LanguageModel with the specified provider, model ID, and configuration.
    ///
    /// - Parameters:
    ///   - provider: The AI provider that will handle requests for this model
    ///   - modelId: The specific model identifier
    ///   - configuration: The configuration parameters (defaults to `.default`)
    public init(provider: any AIProvider, modelId: String, configuration: ModelConfiguration = .default) {
        self.provider = provider
        self.modelId = modelId
        self.configuration = configuration
    }
}

// MARK: - Configuration Builder Methods

/// Builder pattern methods for creating configured model instances.
///
/// These methods provide a fluent interface for configuring model parameters,
/// following Swift conventions and enabling easy chaining of configuration calls.
public extension LanguageModel {
    
    /// Set the temperature for text generation.
    ///
    /// Temperature controls randomness in the output. Higher values (e.g., 0.8) make
    /// output more random, while lower values (e.g., 0.2) make it more focused and deterministic.
    ///
    /// - Parameter value: Temperature value, typically between 0.0 and 1.0
    /// - Returns: A new `LanguageModel` instance with the updated temperature
    ///
    /// ## Example
    /// ```swift
    /// let creativeModel = model.temperature(0.9)  // More creative/random
    /// let focusedModel = model.temperature(0.1)   // More focused/deterministic
    /// ```
    func temperature(_ value: Double) -> LanguageModel {
        LanguageModel(
            provider: provider,
            modelId: modelId,
            configuration: configuration.temperature(value)
        )
    }
    
    /// Set the maximum number of tokens to generate.
    ///
    /// This parameter limits the length of the model's response. The exact meaning
    /// of "token" depends on the provider's tokenization scheme.
    ///
    /// - Parameter value: Maximum number of tokens to generate
    /// - Returns: A new `LanguageModel` instance with the updated max tokens
    ///
    /// ## Example
    /// ```swift
    /// let shortResponse = model.maxTokens(50)   // Brief responses
    /// let longResponse = model.maxTokens(1000)  // Detailed responses
    /// ```
    func maxTokens(_ value: Int) -> LanguageModel {
        LanguageModel(
            provider: provider,
            modelId: modelId,
            configuration: configuration.maxTokens(value)
        )
    }
    
    /// Set the top-p (nucleus) sampling parameter.
    ///
    /// Top-p sampling considers only the smallest set of tokens whose cumulative
    /// probability mass exceeds the threshold p. This provides dynamic vocabulary
    /// selection based on the context.
    ///
    /// - Parameter value: Top-p value, typically between 0.0 and 1.0
    /// - Returns: A new `LanguageModel` instance with the updated top-p
    ///
    /// ## Example
    /// ```swift
    /// let focusedModel = model.topP(0.1)   // Focus on most likely tokens
    /// let diverseModel = model.topP(0.9)   // Allow more diverse token selection
    /// ```
    func topP(_ value: Double) -> LanguageModel {
        LanguageModel(
            provider: provider,
            modelId: modelId,
            configuration: configuration.topP(value)
        )
    }
    
    /// Set provider-specific configuration parameters.
    ///
    /// This method allows setting parameters that are specific to a particular
    /// AI provider and not part of the standard configuration interface.
    ///
    /// - Parameter value: Dictionary of provider-specific parameters
    /// - Returns: A new `LanguageModel` instance with the updated provider-specific settings
    ///
    /// ## Example
    /// ```swift
    /// let model = baseModel.providerSpecific([
    ///     "repetition_penalty": "1.1",
    ///     "custom_parameter": "value"
    /// ])
    /// ```
    func providerSpecific(_ value: [String: String]) -> LanguageModel {
        LanguageModel(
            provider: provider,
            modelId: modelId,
            configuration: configuration.providerSpecific(value)
        )
    }
    
    /// Configure tools for the model (placeholder for future implementation).
    ///
    /// In the new architecture, tools would be handled differently, likely at the
    /// request level rather than the model level. This method is provided for
    /// API compatibility but currently returns the model unchanged.
    ///
    /// - Parameter tools: Array of tools to make available to the model
    /// - Returns: The same `LanguageModel` instance (placeholder implementation)
    ///
    /// ## Note
    /// This is a placeholder method. In the final implementation, tools would likely
    /// be passed at the request level through `AIClient` methods rather than being
    /// configured on the model itself.
    func tools(_ tools: [Tool]) -> LanguageModel {
        // Tools would be handled differently in the new architecture
        // This is a placeholder for API compatibility
        return self
    }
}

// MARK: - Utility Methods

public extension LanguageModel {
    
    /// Get a human-readable description of this model configuration.
    ///
    /// This method provides a useful description for debugging and logging purposes,
    /// including the provider name, model ID, and key configuration parameters.
    ///
    /// - Returns: A string describing the model configuration
    var description: String {
        var components = ["\(provider.name):\(modelId)"]
        
        if let temp = configuration.temperature {
            components.append("temp=\(temp)")
        }
        if let maxTokens = configuration.maxTokens {
            components.append("maxTokens=\(maxTokens)")
        }
        if let topP = configuration.topP {
            components.append("topP=\(topP)")
        }
        
        return components.joined(separator: ", ")
    }
    
    /// Check if this model configuration is valid for the provider.
    ///
    /// This method delegates validation to the provider, which can check if the
    /// model ID is supported and if the configuration parameters are valid.
    ///
    /// - Returns: `true` if the configuration is valid, `false` otherwise
    ///
    /// ## Example
    /// ```swift
    /// let model = provider.languageModel("invalid-model-id")
    /// if !model.isValid {
    ///     print("Invalid model configuration")
    /// }
    /// ```
    var isValid: Bool {
        do {
            try provider.validateConfiguration(configuration)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Equatable Conformance

extension LanguageModel: Equatable {
    
    /// Compare two LanguageModel instances for equality.
    ///
    /// Two models are considered equal if they have the same provider name,
    /// model ID, and configuration. Provider instances are compared by name
    /// since providers don't generally conform to Equatable.
    ///
    /// - Parameters:
    ///   - lhs: First model to compare
    ///   - rhs: Second model to compare
    /// - Returns: `true` if the models are equivalent, `false` otherwise
    public static func == (lhs: LanguageModel, rhs: LanguageModel) -> Bool {
        return lhs.provider.name == rhs.provider.name &&
               lhs.modelId == rhs.modelId &&
               lhs.configuration == rhs.configuration
    }
}

// MARK: - Hashable Conformance

extension LanguageModel: Hashable {
    
    /// Hash this LanguageModel instance.
    ///
    /// The hash is computed from the provider name, model ID, and configuration
    /// to ensure that equivalent models have the same hash value.
    ///
    /// - Parameter hasher: The hasher to use
    public func hash(into hasher: inout Hasher) {
        hasher.combine(provider.name)
        hasher.combine(modelId)
        hasher.combine(configuration)
    }
}