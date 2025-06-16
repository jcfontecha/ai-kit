import Foundation

// MARK: - ModelConfiguration

/// Configuration for model behavior and parameters.
///
/// `ModelConfiguration` encapsulates all the parameters that control how an AI model
/// behaves during text generation. It provides a comprehensive set of options that
/// are commonly supported across different AI providers, along with extensibility
/// for provider-specific parameters.
///
/// ## Parameter Categories
///
/// ### Generation Control
/// - **temperature**: Controls randomness (0.0 = deterministic, 1.0 = very random)
/// - **topP**: Nucleus sampling threshold for dynamic vocabulary selection
/// - **topK**: Limits vocabulary to top K most likely tokens
///
/// ### Output Control
/// - **maxTokens**: Maximum number of tokens to generate
/// - **stopSequences**: Sequences that will stop generation when encountered
///
/// ### Content Control
/// - **frequencyPenalty**: Reduces likelihood of repeating tokens based on frequency
/// - **presencePenalty**: Reduces likelihood of repeating any tokens that appeared
///
/// ### Reproducibility
/// - **seed**: Random seed for deterministic generation (when supported)
///
/// ### Provider Extensions
/// - **providerSpecific**: Dictionary for provider-specific parameters
///
/// ## Usage Examples
///
/// ### Basic Configuration
/// ```swift
/// let config = ModelConfiguration()
///     .temperature(0.7)
///     .maxTokens(150)
/// ```
///
/// ### Creative Writing Configuration
/// ```swift
/// let creative = ModelConfiguration()
///     .temperature(0.9)
///     .topP(0.95)
///     .frequencyPenalty(0.5)
/// ```
///
/// ### Precise/Factual Configuration
/// ```swift
/// let precise = ModelConfiguration()
///     .temperature(0.1)
///     .topP(0.1)
///     .seed(42)
/// ```
public struct ModelConfiguration: Sendable {
    
    // MARK: - Properties
    
    /// Controls randomness in generation.
    ///
    /// - `0.0`: Completely deterministic (always picks most likely token)
    /// - `0.3`: Conservative, focused responses
    /// - `0.7`: Balanced creativity and coherence
    /// - `1.0`: Maximum randomness
    public let temperature: Double?
    
    /// Maximum number of tokens to generate.
    ///
    /// The exact meaning of "token" depends on the provider's tokenization.
    /// Generally, 1 token ≈ 0.75 words for English text.
    public let maxTokens: Int?
    
    /// Top-p (nucleus) sampling parameter.
    ///
    /// Only considers tokens whose cumulative probability mass exceeds this threshold.
    /// - `0.1`: Very focused, only most likely tokens
    /// - `0.9`: Allows diverse token selection
    /// - `1.0`: No filtering (uses all tokens)
    public let topP: Double?
    
    /// Top-k sampling parameter.
    ///
    /// Limits consideration to the K most likely tokens at each step.
    /// - `1`: Only the most likely token (equivalent to greedy decoding)
    /// - `40`: A common balanced value
    /// - `nil`: No top-k filtering
    public let topK: Int?
    
    /// Frequency penalty for reducing repetition.
    ///
    /// Reduces likelihood of tokens based on how often they've appeared.
    /// - `0.0`: No penalty
    /// - `1.0`: Strong penalty against repetition
    /// - `2.0`: Very strong penalty (may harm coherence)
    public let frequencyPenalty: Double?
    
    /// Presence penalty for reducing repetition.
    ///
    /// Reduces likelihood of any token that has already appeared, regardless of frequency.
    /// - `0.0`: No penalty
    /// - `1.0`: Strong penalty against any repetition
    /// - `2.0`: Very strong penalty
    public let presencePenalty: Double?
    
    /// Sequences that will stop generation when encountered.
    ///
    /// Generation stops immediately when any of these sequences is produced.
    /// Common examples: `["\n\n", "Human:", "Assistant:"]`
    public let stopSequences: [String]?
    
    /// Random seed for deterministic generation.
    ///
    /// When supported by the provider, using the same seed with the same input
    /// and parameters should produce identical output.
    public let seed: Int?
    
    /// Provider-specific parameters.
    ///
    /// This dictionary allows passing parameters that are specific to particular
    /// AI providers and not part of the standard interface.
    ///
    /// Examples:
    /// - OpenAI: `["logit_bias": "{\"50256\": -100}"]`
    /// - Anthropic: `["system_prompt_role": "user"]`
    public let providerSpecific: [String: String]?
    
    // MARK: - Initialization
    
    /// Creates a new ModelConfiguration with the specified parameters.
    ///
    /// All parameters are optional and default to `nil`, which means the provider's
    /// default values will be used.
    ///
    /// - Parameters:
    ///   - temperature: Controls randomness (0.0-1.0)
    ///   - maxTokens: Maximum tokens to generate
    ///   - topP: Top-p sampling threshold (0.0-1.0)
    ///   - topK: Top-k sampling limit
    ///   - frequencyPenalty: Frequency penalty (typically 0.0-2.0)
    ///   - presencePenalty: Presence penalty (typically 0.0-2.0)
    ///   - stopSequences: Stop sequences for generation
    ///   - seed: Random seed for reproducibility
    ///   - providerSpecific: Provider-specific parameters
    public init(
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        frequencyPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        stopSequences: [String]? = nil,
        seed: Int? = nil,
        providerSpecific: [String: String]? = nil
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.topK = topK
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.stopSequences = stopSequences
        self.seed = seed
        self.providerSpecific = providerSpecific
    }
    
    /// Default configuration with no parameters set.
    ///
    /// This configuration uses provider defaults for all parameters.
    public static let `default` = ModelConfiguration()
}

// MARK: - Builder Pattern Methods

/// Builder pattern methods for creating configured instances.
///
/// These methods provide a fluent interface for setting configuration parameters,
/// allowing for easy chaining and readable configuration code.
public extension ModelConfiguration {
    
    /// Set the temperature parameter.
    ///
    /// - Parameter value: Temperature value (typically 0.0-1.0)
    /// - Returns: A new `ModelConfiguration` with the updated temperature
    func temperature(_ value: Double) -> ModelConfiguration {
        ModelConfiguration(
            temperature: value,
            maxTokens: maxTokens,
            topP: topP,
            topK: topK,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty,
            stopSequences: stopSequences,
            seed: seed,
            providerSpecific: providerSpecific
        )
    }
    
    /// Set the maximum tokens parameter.
    ///
    /// - Parameter value: Maximum number of tokens to generate
    /// - Returns: A new `ModelConfiguration` with the updated max tokens
    func maxTokens(_ value: Int) -> ModelConfiguration {
        ModelConfiguration(
            temperature: temperature,
            maxTokens: value,
            topP: topP,
            topK: topK,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty,
            stopSequences: stopSequences,
            seed: seed,
            providerSpecific: providerSpecific
        )
    }
    
    /// Set the top-p parameter.
    ///
    /// - Parameter value: Top-p value (typically 0.0-1.0)
    /// - Returns: A new `ModelConfiguration` with the updated top-p
    func topP(_ value: Double) -> ModelConfiguration {
        ModelConfiguration(
            temperature: temperature,
            maxTokens: maxTokens,
            topP: value,
            topK: topK,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty,
            stopSequences: stopSequences,
            seed: seed,
            providerSpecific: providerSpecific
        )
    }
    
    /// Set the top-k parameter.
    ///
    /// - Parameter value: Top-k value
    /// - Returns: A new `ModelConfiguration` with the updated top-k
    func topK(_ value: Int) -> ModelConfiguration {
        ModelConfiguration(
            temperature: temperature,
            maxTokens: maxTokens,
            topP: topP,
            topK: value,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty,
            stopSequences: stopSequences,
            seed: seed,
            providerSpecific: providerSpecific
        )
    }
    
    /// Set the frequency penalty parameter.
    ///
    /// - Parameter value: Frequency penalty value (typically 0.0-2.0)
    /// - Returns: A new `ModelConfiguration` with the updated frequency penalty
    func frequencyPenalty(_ value: Double) -> ModelConfiguration {
        ModelConfiguration(
            temperature: temperature,
            maxTokens: maxTokens,
            topP: topP,
            topK: topK,
            frequencyPenalty: value,
            presencePenalty: presencePenalty,
            stopSequences: stopSequences,
            seed: seed,
            providerSpecific: providerSpecific
        )
    }
    
    /// Set the presence penalty parameter.
    ///
    /// - Parameter value: Presence penalty value (typically 0.0-2.0)
    /// - Returns: A new `ModelConfiguration` with the updated presence penalty
    func presencePenalty(_ value: Double) -> ModelConfiguration {
        ModelConfiguration(
            temperature: temperature,
            maxTokens: maxTokens,
            topP: topP,
            topK: topK,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: value,
            stopSequences: stopSequences,
            seed: seed,
            providerSpecific: providerSpecific
        )
    }
    
    /// Set the stop sequences parameter.
    ///
    /// - Parameter value: Array of stop sequences
    /// - Returns: A new `ModelConfiguration` with the updated stop sequences
    func stopSequences(_ value: [String]) -> ModelConfiguration {
        ModelConfiguration(
            temperature: temperature,
            maxTokens: maxTokens,
            topP: topP,
            topK: topK,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty,
            stopSequences: value,
            seed: seed,
            providerSpecific: providerSpecific
        )
    }
    
    /// Set the seed parameter.
    ///
    /// - Parameter value: Random seed for reproducibility
    /// - Returns: A new `ModelConfiguration` with the updated seed
    func seed(_ value: Int) -> ModelConfiguration {
        ModelConfiguration(
            temperature: temperature,
            maxTokens: maxTokens,
            topP: topP,
            topK: topK,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty,
            stopSequences: stopSequences,
            seed: value,
            providerSpecific: providerSpecific
        )
    }
    
    /// Set provider-specific parameters.
    ///
    /// - Parameter value: Dictionary of provider-specific parameters
    /// - Returns: A new `ModelConfiguration` with the updated provider-specific settings
    func providerSpecific(_ value: [String: String]) -> ModelConfiguration {
        ModelConfiguration(
            temperature: temperature,
            maxTokens: maxTokens,
            topP: topP,
            topK: topK,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty,
            stopSequences: stopSequences,
            seed: seed,
            providerSpecific: value
        )
    }
}

// MARK: - Predefined Configurations

public extension ModelConfiguration {
    
    /// Configuration optimized for creative writing and brainstorming.
    ///
    /// Uses higher temperature and top-p for more diverse and creative outputs.
    static let creative = ModelConfiguration()
        .temperature(0.9)
        .topP(0.95)
        .frequencyPenalty(0.3)
    
    /// Configuration optimized for precise, factual responses.
    ///
    /// Uses low temperature and top-p for focused, deterministic outputs.
    static let precise = ModelConfiguration()
        .temperature(0.1)
        .topP(0.1)
    
    /// Configuration providing a balance between creativity and precision.
    ///
    /// Uses moderate values suitable for general-purpose text generation.
    static let balanced = ModelConfiguration()
        .temperature(0.5)
        .topP(0.8)
    
    /// Configuration optimized for chat conversations.
    ///
    /// Balances coherence with natural variability in responses.
    static let chat = ModelConfiguration()
        .temperature(0.7)
        .topP(0.9)
        .maxTokens(500)
}

// MARK: - Validation

public extension ModelConfiguration {
    
    /// Validate the configuration parameters.
    ///
    /// Checks that all parameters are within reasonable ranges and compatible
    /// with each other.
    ///
    /// - Throws: `AIConfigurationError` if validation fails
    func validate() throws {
        if let temp = temperature, temp < 0.0 || temp > 2.0 {
            throw AIConfigurationError.invalidParameter("temperature", "must be between 0.0 and 2.0")
        }
        
        if let maxTokens = maxTokens, maxTokens <= 0 {
            throw AIConfigurationError.invalidParameter("maxTokens", "must be positive")
        }
        
        if let topP = topP, topP < 0.0 || topP > 1.0 {
            throw AIConfigurationError.invalidParameter("topP", "must be between 0.0 and 1.0")
        }
        
        if let topK = topK, topK <= 0 {
            throw AIConfigurationError.invalidParameter("topK", "must be positive")
        }
        
        if let freqPenalty = frequencyPenalty, freqPenalty < 0.0 || freqPenalty > 2.0 {
            throw AIConfigurationError.invalidParameter("frequencyPenalty", "must be between 0.0 and 2.0")
        }
        
        if let presPenalty = presencePenalty, presPenalty < 0.0 || presPenalty > 2.0 {
            throw AIConfigurationError.invalidParameter("presencePenalty", "must be between 0.0 and 2.0")
        }
        
        if let stopSeqs = stopSequences, stopSeqs.isEmpty {
            throw AIConfigurationError.invalidParameter("stopSequences", "cannot be empty array")
        }
    }
}

// MARK: - Codable Conformance

extension ModelConfiguration: Codable {
    
    /// Custom encoding to handle the dictionary properly
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(topK, forKey: .topK)
        try container.encodeIfPresent(frequencyPenalty, forKey: .frequencyPenalty)
        try container.encodeIfPresent(presencePenalty, forKey: .presencePenalty)
        try container.encodeIfPresent(stopSequences, forKey: .stopSequences)
        try container.encodeIfPresent(seed, forKey: .seed)
        try container.encodeIfPresent(providerSpecific, forKey: .providerSpecific)
    }
    
    private enum CodingKeys: String, CodingKey {
        case temperature
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case topK = "top_k"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
        case stopSequences = "stop_sequences"
        case seed
        case providerSpecific = "provider_specific"
    }
}

// MARK: - Equatable Conformance

extension ModelConfiguration: Equatable {
    
    /// Compare two ModelConfiguration instances for equality.
    public static func == (lhs: ModelConfiguration, rhs: ModelConfiguration) -> Bool {
        return lhs.temperature == rhs.temperature &&
               lhs.maxTokens == rhs.maxTokens &&
               lhs.topP == rhs.topP &&
               lhs.topK == rhs.topK &&
               lhs.frequencyPenalty == rhs.frequencyPenalty &&
               lhs.presencePenalty == rhs.presencePenalty &&
               lhs.stopSequences == rhs.stopSequences &&
               lhs.seed == rhs.seed &&
               lhs.providerSpecific == rhs.providerSpecific
    }
}

// MARK: - Hashable Conformance

extension ModelConfiguration: Hashable {
    
    /// Hash this ModelConfiguration instance.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(temperature)
        hasher.combine(maxTokens)
        hasher.combine(topP)
        hasher.combine(topK)
        hasher.combine(frequencyPenalty)
        hasher.combine(presencePenalty)
        hasher.combine(stopSequences)
        hasher.combine(seed)
        hasher.combine(providerSpecific)
    }
}