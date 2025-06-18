import Foundation

// MARK: - TranscriptionModel

/// Configuration container for transcription operations.
///
/// `TranscriptionModel` follows the same builder pattern as `LanguageModel`, providing
/// a type-safe way to configure transcription parameters. It encapsulates the provider,
/// model ID, and configuration settings for transcription operations.
///
/// ## Responsibilities
/// - **Configuration Storage**: Hold transcription-specific parameters
/// - **Builder Pattern**: Provide fluent interface for configuration
/// - **Provider Binding**: Associate with specific AI provider
/// - **Validation**: Ensure configuration is valid for the provider
///
/// ## Usage Examples
///
/// ### Basic Configuration
/// ```swift
/// let model = provider.transcriptionModel("whisper-1")
/// let response = try await client.transcribe(model: model, audio: audio)
/// ```
///
/// ### Advanced Configuration
/// ```swift
/// let model = provider.transcriptionModel("whisper-1")
///     .language("en")
///     .prompt("This is a technical discussion about AI.")
///     .temperature(0.2)
///     .responseFormat(.verboseJson)
/// 
/// let response = try await client.transcribe(model: model, audio: audio)
/// ```
///
/// ### Provider-Specific Options (following Vercel AI SDK pattern)
/// ```swift
/// let model = provider.transcriptionModel("whisper-1")
///     .language("en")
///     .providerOptions(["openai": ["timestampGranularities": ["word", "segment"]]])
/// ```
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct TranscriptionModel: Sendable {
    
    // MARK: - Properties
    
    /// The AI provider that will handle transcription requests.
    ///
    /// This provider must implement the transcription methods in the AIProvider protocol.
    public let provider: any AIProvider
    
    /// The specific transcription model identifier.
    ///
    /// This should match a model ID supported by the provider.
    /// Examples: "whisper-1" (OpenAI), "nova-2" (Deepgram), "best" (AssemblyAI)
    public let modelId: String
    
    /// Configuration parameters for transcription.
    ///
    /// Contains language settings, prompts, format options, and other
    /// transcription-specific parameters.
    public let configuration: TranscriptionConfiguration
    
    /// Provider-specific options.
    ///
    /// Additional configuration that is specific to the provider and
    /// may not be standardized across all providers.
    public let providerOptions: [String: String]?
    
    /// Additional HTTP headers for transcription requests.
    ///
    /// Custom headers that will be included in API requests.
    /// Useful for authentication, tracking, or provider-specific options.
    public let headers: [String: String]?
    
    /// Maximum number of retry attempts for failed requests.
    ///
    /// Controls how many times the transcription request will be retried
    /// in case of transient failures. Default behavior is provider-specific.
    public let maxRetries: Int?
    
    // MARK: - Initialization
    
    /// Creates a new transcription model with the specified parameters.
    ///
    /// - Parameters:
    ///   - provider: The AI provider for transcription
    ///   - modelId: The specific model identifier
    ///   - configuration: Transcription configuration parameters
    ///   - providerOptions: Provider-specific options
    ///   - headers: Additional HTTP headers
    ///   - maxRetries: Maximum retry attempts
    public init(
        provider: any AIProvider,
        modelId: String,
        configuration: TranscriptionConfiguration = TranscriptionConfiguration(),
        providerOptions: [String: String]? = nil,
        headers: [String: String]? = nil,
        maxRetries: Int? = nil
    ) {
        self.provider = provider
        self.modelId = modelId
        self.configuration = configuration
        self.providerOptions = providerOptions
        self.headers = headers
        self.maxRetries = maxRetries
    }
    
    // MARK: - Builder Pattern Methods
    
    /// Set the language for transcription.
    ///
    /// - Parameter language: ISO-639-1 language code (e.g., "en", "es", "fr")
    /// - Returns: A new TranscriptionModel with the updated language setting
    public func language(_ language: String) -> TranscriptionModel {
        return TranscriptionModel(
            provider: provider,
            modelId: modelId,
            configuration: configuration.language(language),
            providerOptions: providerOptions,
            headers: headers,
            maxRetries: maxRetries
        )
    }
    
    /// Set the prompt for transcription.
    ///
    /// - Parameter prompt: Text prompt to guide transcription style and accuracy
    /// - Returns: A new TranscriptionModel with the updated prompt setting
    public func prompt(_ prompt: String) -> TranscriptionModel {
        return TranscriptionModel(
            provider: provider,
            modelId: modelId,
            configuration: configuration.prompt(prompt),
            providerOptions: providerOptions,
            headers: headers,
            maxRetries: maxRetries
        )
    }
    
    /// Set the response format for transcription.
    ///
    /// - Parameter responseFormat: The desired format for transcription output
    /// - Returns: A new TranscriptionModel with the updated response format setting
    public func responseFormat(_ responseFormat: TranscriptionResponseFormat) -> TranscriptionModel {
        return TranscriptionModel(
            provider: provider,
            modelId: modelId,
            configuration: configuration.responseFormat(responseFormat),
            providerOptions: providerOptions,
            headers: headers,
            maxRetries: maxRetries
        )
    }
    
    /// Set the temperature for transcription.
    ///
    /// - Parameter temperature: Randomness level (0.0-1.0, lower is more deterministic)
    /// - Returns: A new TranscriptionModel with the updated temperature setting
    public func temperature(_ temperature: Double) -> TranscriptionModel {
        return TranscriptionModel(
            provider: provider,
            modelId: modelId,
            configuration: configuration.temperature(temperature),
            providerOptions: providerOptions,
            headers: headers,
            maxRetries: maxRetries
        )
    }
    
    
    /// Set provider-specific options for transcription.
    ///
    /// - Parameter providerOptions: Dictionary of provider-specific configuration
    /// - Returns: A new TranscriptionModel with the updated provider options
    ///
    /// ## Example
    /// ```swift
    /// let model = provider.transcriptionModel("whisper-1")
    ///     .providerOptions([
    ///         "timestamp_granularities": "word",
    ///         "response_format": "verbose_json"
    ///     ])
    /// ```
    public func providerOptions(_ providerOptions: [String: String]) -> TranscriptionModel {
        return TranscriptionModel(
            provider: provider,
            modelId: modelId,
            configuration: configuration,
            providerOptions: providerOptions,
            headers: headers,
            maxRetries: maxRetries
        )
    }
    
    /// Set additional HTTP headers for transcription requests.
    ///
    /// - Parameter headers: Dictionary of HTTP headers
    /// - Returns: A new TranscriptionModel with the updated headers
    public func headers(_ headers: [String: String]) -> TranscriptionModel {
        return TranscriptionModel(
            provider: provider,
            modelId: modelId,
            configuration: configuration,
            providerOptions: providerOptions,
            headers: headers,
            maxRetries: maxRetries
        )
    }
    
    /// Set the maximum number of retry attempts.
    ///
    /// - Parameter maxRetries: Maximum number of retry attempts for failed requests
    /// - Returns: A new TranscriptionModel with the updated retry setting
    public func maxRetries(_ maxRetries: Int) -> TranscriptionModel {
        return TranscriptionModel(
            provider: provider,
            modelId: modelId,
            configuration: configuration,
            providerOptions: providerOptions,
            headers: headers,
            maxRetries: maxRetries
        )
    }
}

// MARK: - TranscriptionModel Extensions

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension TranscriptionModel {
    
    /// Validate the transcription model configuration.
    ///
    /// Checks that the configuration is supported by the provider and that
    /// all parameters are within valid ranges.
    ///
    /// - Throws: `TranscriptionError` if the configuration is invalid
    func validateConfiguration() throws {
        // Validate temperature range
        if let temperature = configuration.temperature {
            guard temperature >= 0.0 && temperature <= 1.0 else {
                throw TranscriptionError.invalidConfiguration(
                    "Temperature must be between 0.0 and 1.0, got \(temperature)"
                )
            }
        }
        
        // Validate language code format (basic check for ISO-639-1)
        if let language = configuration.language {
            guard language.count == 2 && language.allSatisfy(\.isLetter) else {
                throw TranscriptionError.invalidConfiguration(
                    "Language must be a 2-letter ISO-639-1 code, got '\(language)'"
                )
            }
        }
        
        // Let the provider perform additional validation
        // Note: We would call provider.validateTranscriptionConfiguration here
        // once we extend the AIProvider protocol
    }
    
    /// Get a debug description of the transcription model.
    var debugDescription: [String: Any] {
        var description: [String: Any] = [
            "provider": provider.name,
            "modelId": modelId
        ]
        
        if let language = configuration.language {
            description["language"] = language
        }
        
        if let responseFormat = configuration.responseFormat {
            description["responseFormat"] = responseFormat.rawValue
        }
        
        if let temperature = configuration.temperature {
            description["temperature"] = temperature
        }
        
        
        if let maxRetries = maxRetries {
            description["maxRetries"] = maxRetries
        }
        
        return description
    }
    
    /// Create a provider request from this transcription model.
    ///
    /// - Parameters:
    ///   - audio: The audio input to transcribe
    ///   - requestId: Optional custom request ID
    /// - Returns: A TranscriptionProviderRequest ready for the provider
    func createProviderRequest(
        audio: AudioInput,
        requestId: String = UUID().uuidString
    ) -> TranscriptionProviderRequest {
        return TranscriptionProviderRequest(
            modelId: modelId,
            audio: audio,
            configuration: configuration,
            providerOptions: providerOptions,
            headers: headers,
            requestId: requestId
        )
    }
}