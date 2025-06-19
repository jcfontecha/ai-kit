import Foundation

// MARK: - Transcription Types

/// Audio input types for transcription requests.
///
/// Supports multiple audio input formats following Swift idioms and the Vercel AI SDK pattern.
/// Providers should handle format conversion and validation as needed.
///
/// ## Usage Examples
/// ```swift
/// // From local file
/// let audio = AudioInput.fileURL(URL(fileURLWithPath: "audio.mp3"))
/// 
/// // From remote URL
/// let audio = AudioInput.url(URL(string: "https://example.com/audio.mp3")!)
/// 
/// // From raw data
/// let audioData = try Data(contentsOf: audioURL)
/// let audio = AudioInput.data(audioData)
/// 
/// // From base64 string
/// let audio = AudioInput.base64String(base64AudioString)
/// ```
public enum AudioInput: Sendable {
    
    /// Raw audio data.
    ///
    /// Use this when you already have the audio loaded into memory as Data.
    /// Providers will determine the audio format from the data headers.
    case data(Data)
    
    /// Remote URL to an audio file.
    ///
    /// The audio will be downloaded by the provider as needed.
    /// Supports HTTP/HTTPS URLs pointing to audio files.
    case url(URL)
    
    /// Local file URL to an audio file.
    ///
    /// Use this for local files on the device. The audio will be read
    /// from the file system when needed.
    case fileURL(URL)
    
    /// Base64 encoded audio data.
    ///
    /// Useful when receiving audio data from APIs or when the audio
    /// is embedded in other data structures.
    case base64String(String)
}

// MARK: - AudioInput Extensions

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public extension AudioInput {
    
    /// Get the audio data asynchronously.
    ///
    /// This method handles the conversion of different AudioInput types
    /// to raw Data that can be used by providers.
    ///
    /// - Returns: The audio data
    /// - Throws: `TranscriptionError` if the audio cannot be loaded
    func audioData() async throws -> Data {
        switch self {
        case .data(let data):
            return data
        case .url(let url):
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        case .fileURL(let url):
            return try Data(contentsOf: url)
        case .base64String(let base64):
            guard let data = Data(base64Encoded: base64) else {
                throw TranscriptionError.unsupportedAudioFormat("Invalid base64 audio data")
            }
            return data
        }
    }
    
    /// Get a description of the audio input for debugging.
    var debugDescription: String {
        switch self {
        case .data(let data):
            return "data(\(data.count) bytes)"
        case .url(let url):
            return "url(\(url.absoluteString))"
        case .fileURL(let url):
            return "fileURL(\(url.lastPathComponent))"
        case .base64String(let base64):
            return "base64String(\(base64.prefix(50))...)"
        }
    }
}

// MARK: - Transcription Configuration

/// Configuration options for transcription requests.
///
/// This structure contains all the configuration parameters that can be used
/// to customize transcription behavior. Providers should map these to their
/// specific API parameters.
///
/// ## Usage Examples
/// ```swift
/// let config = TranscriptionConfiguration()
///     .language("en")
///     .prompt("This is a technical discussion about AI.")
///     .temperature(0.2)
/// ```
public struct TranscriptionConfiguration: Sendable {
    
    /// Language of the input audio (ISO-639-1 format).
    ///
    /// Providing the language can improve accuracy and latency.
    /// Examples: "en" for English, "es" for Spanish, "fr" for French.
    public let language: String?
    
    /// Text prompt to guide the model's style.
    ///
    /// Can be used to improve accuracy for specific domains, proper nouns,
    /// or technical terminology that might appear in the audio.
    public let prompt: String?
    
    /// Response format for the transcription.
    ///
    /// Different formats provide different levels of detail and structure.
    /// Some providers may not support all formats.
    public let responseFormat: TranscriptionResponseFormat?
    
    /// Temperature for randomness in transcription.
    ///
    /// Lower values (0.0-0.3) are more deterministic and conservative.
    /// Higher values may produce more varied but less accurate results.
    /// Most providers support 0.0-1.0 range.
    public let temperature: Double?
    
    
    // MARK: - Initialization
    
    public init(
        language: String? = nil,
        prompt: String? = nil,
        responseFormat: TranscriptionResponseFormat? = nil,
        temperature: Double? = nil
    ) {
        self.language = language
        self.prompt = prompt
        self.responseFormat = responseFormat
        self.temperature = temperature
    }
    
    // MARK: - Builder Pattern Methods
    
    /// Set the language for transcription.
    public func language(_ language: String) -> TranscriptionConfiguration {
        return TranscriptionConfiguration(
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )
    }
    
    /// Set the prompt for transcription.
    public func prompt(_ prompt: String) -> TranscriptionConfiguration {
        return TranscriptionConfiguration(
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )
    }
    
    /// Set the response format for transcription.
    public func responseFormat(_ responseFormat: TranscriptionResponseFormat) -> TranscriptionConfiguration {
        return TranscriptionConfiguration(
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )
    }
    
    /// Set the temperature for transcription.
    public func temperature(_ temperature: Double) -> TranscriptionConfiguration {
        return TranscriptionConfiguration(
            language: language,
            prompt: prompt,
            responseFormat: responseFormat,
            temperature: temperature
        )
    }
    
}

// MARK: - Transcription Response Format

/// Supported response formats for transcription.
///
/// Different formats provide different levels of detail and structure.
/// Not all providers support all formats.
public enum TranscriptionResponseFormat: String, Sendable, CaseIterable {
    
    /// JSON format with basic transcription data.
    case json = "json"
    
    /// Plain text format with just the transcribed text.
    case text = "text"
    
    /// WebVTT format for subtitles.
    case vtt = "vtt"
    
    /// SubRip Text format for subtitles.
    case srt = "srt"
    
    /// Verbose JSON format with detailed timing and metadata.
    case verboseJson = "verbose_json"
}


// MARK: - Transcription Response

/// The complete result of a transcription operation.
///
/// Contains the transcribed text along with metadata, timing information,
/// and provider-specific details.
///
/// ## Usage Examples
/// ```swift
/// let response = try await client.transcribe(model: model, audio: audio)
/// 
/// print("Text: \(response.text)")
/// print("Language: \(response.language ?? "unknown")")
/// print("Duration: \(response.durationInSeconds ?? 0) seconds")
/// 
/// for segment in response.segments {
///     print("\(segment.startSecond)s-\(segment.endSecond)s: \(segment.text)")
/// }
/// ```
public struct TranscriptionResponse: Sendable {
    
    /// The complete transcribed text from the audio input.
    ///
    /// This is the primary output of the transcription operation,
    /// containing the full text content extracted from the audio.
    public let text: String
    
    /// Array of transcript segments with timing information.
    ///
    /// Each segment represents a portion of the transcribed text
    /// along with its start and end times in seconds.
    public let segments: [TranscriptionSegment]
    
    /// The detected or specified language of the transcript.
    ///
    /// Language code in ISO-639-1 format (e.g., "en" for English).
    /// May be nil if the provider doesn't support language detection.
    public let language: String?
    
    /// Total duration of the transcribed audio in seconds.
    ///
    /// May be nil if the provider doesn't provide duration information.
    public let durationInSeconds: Double?
    
    /// Warnings from the transcription provider.
    ///
    /// Contains any warnings about unsupported settings, quality issues,
    /// or other non-fatal problems encountered during transcription.
    public let warnings: [TranscriptionWarning]
    
    /// Response metadata from the provider.
    ///
    /// Contains information about the API calls made, timing, model used, etc.
    /// There may be multiple responses if retries or multiple calls were made.
    public let responses: [TranscriptionResponseMetadata]
    
    /// Provider-specific metadata.
    ///
    /// Contains additional information that may be specific to the provider
    /// and not standardized across all providers.
    public let providerMetadata: [String: [String: String]]?
    
    // MARK: - Initialization
    
    public init(
        text: String,
        segments: [TranscriptionSegment] = [],
        language: String? = nil,
        durationInSeconds: Double? = nil,
        warnings: [TranscriptionWarning] = [],
        responses: [TranscriptionResponseMetadata] = [],
        providerMetadata: [String: [String: String]]? = nil
    ) {
        self.text = text
        self.segments = segments
        self.language = language
        self.durationInSeconds = durationInSeconds
        self.warnings = warnings
        self.responses = responses
        self.providerMetadata = providerMetadata
    }
}

// MARK: - Transcription Segment

/// A segment of transcribed text with timing information.
///
/// Represents a portion of the transcribed audio with start and end times.
/// The granularity depends on the timestamp granularity setting used.
public struct TranscriptionSegment: Sendable {
    
    /// The text content of this segment.
    public let text: String
    
    /// Start time of this segment in seconds.
    public let startSecond: Double
    
    /// End time of this segment in seconds.
    public let endSecond: Double
    
    public init(text: String, startSecond: Double, endSecond: Double) {
        self.text = text
        self.startSecond = startSecond
        self.endSecond = endSecond
    }
}

// MARK: - Transcription Warning

/// Warning information from transcription providers.
///
/// Contains non-fatal issues encountered during transcription,
/// such as unsupported settings or quality concerns.
public struct TranscriptionWarning: Sendable {
    
    /// The type of warning.
    public let type: String
    
    /// Human-readable warning message.
    public let message: String
    
    /// Additional metadata about the warning.
    public let metadata: [String: String]?
    
    public init(type: String, message: String, metadata: [String: String]? = nil) {
        self.type = type
        self.message = message
        self.metadata = metadata
    }
}

// MARK: - Transcription Response Metadata

/// Metadata about the transcription response from the provider.
///
/// Contains information about the API call, timing, and provider-specific details.
public struct TranscriptionResponseMetadata: Sendable {
    
    /// Timestamp when the response was generated.
    public let timestamp: Date
    
    /// The model ID that was used for transcription.
    public let modelId: String
    
    /// Response headers from the API call.
    public let headers: [String: String]?
    
    /// Duration of the API call in seconds.
    public let duration: TimeInterval?
    
    /// Additional provider-specific metadata.
    public let metadata: [String: String]?
    
    public init(
        timestamp: Date = Date(),
        modelId: String,
        headers: [String: String]? = nil,
        duration: TimeInterval? = nil,
        metadata: [String: String]? = nil
    ) {
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
        self.duration = duration
        self.metadata = metadata
    }
}

// MARK: - Transcription Errors

/// Errors specific to transcription operations.
///
/// These errors represent issues that can occur during transcription,
/// from audio processing problems to provider-specific failures.
public enum TranscriptionError: Error, Sendable {
    
    /// No transcript was generated from the audio input.
    ///
    /// This can happen if the audio is silent, corrupted, or in an
    /// unsupported format.
    case noTranscriptGenerated(String)
    
    /// The audio format is not supported.
    ///
    /// The provider doesn't support the audio format or encoding
    /// of the input audio.
    case unsupportedAudioFormat(String)
    
    /// The audio file is too large for processing.
    ///
    /// Most providers have limits on audio file size.
    /// The maxSize parameter indicates the maximum supported size in bytes.
    case audioFileTooLarge(maxSize: Int)
    
    /// The specified model is not supported for transcription.
    ///
    /// The provider doesn't support the requested transcription model.
    case unsupportedModel(String)
    
    /// Invalid configuration parameters.
    ///
    /// One or more configuration parameters are invalid or not supported
    /// by the provider.
    case invalidConfiguration(String)
    
    /// Network or connectivity issues.
    ///
    /// Problems downloading audio from URLs or communicating with the provider.
    case networkError(Error)
    
    /// A provider-specific error.
    ///
    /// Errors that are specific to a particular provider and don't fit
    /// into the standard categories.
    case providerSpecific(String, underlyingError: Error?)
}

// MARK: - Transcription Error Extensions

extension TranscriptionError: LocalizedError {
    
    /// Localized description of the transcription error.
    public var errorDescription: String? {
        switch self {
        case .noTranscriptGenerated(let reason):
            return "No transcript was generated: \(reason)"
        case .unsupportedAudioFormat(let format):
            return "Unsupported audio format: \(format)"
        case .audioFileTooLarge(let maxSize):
            let maxSizeMB = Double(maxSize) / (1024 * 1024)
            return "Audio file too large. Maximum size: \(String(format: "%.1f", maxSizeMB)) MB"
        case .unsupportedModel(let model):
            return "Model '\(model)' is not supported for transcription"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .providerSpecific(let message, _):
            return message
        }
    }
}

// MARK: - Provider Types

/// Standardized request format for transcription at the provider layer.
///
/// Contains all information needed by providers to make transcription API calls.
public struct TranscriptionProviderRequest: Sendable {
    
    /// The transcription model to use.
    public let modelId: String
    
    /// The audio input to transcribe.
    public let audio: AudioInput
    
    /// Configuration parameters for transcription.
    public let configuration: TranscriptionConfiguration
    
    /// Provider-specific options.
    public let providerOptions: [String: String]?
    
    /// Additional HTTP headers for the request.
    public let headers: [String: String]?
    
    /// Unique identifier for this request.
    public let requestId: String
    
    /// Timestamp when the request was created.
    public let timestamp: Date
    
    public init(
        modelId: String,
        audio: AudioInput,
        configuration: TranscriptionConfiguration = TranscriptionConfiguration(),
        providerOptions: [String: String]? = nil,
        headers: [String: String]? = nil,
        requestId: String = UUID().uuidString,
        timestamp: Date = Date()
    ) {
        self.modelId = modelId
        self.audio = audio
        self.configuration = configuration
        self.providerOptions = providerOptions
        self.headers = headers
        self.requestId = requestId
        self.timestamp = timestamp
    }
}

/// Standardized response format from transcription providers.
///
/// Providers transform their API responses to this standard format.
public struct TranscriptionProviderResponse: Sendable {
    
    /// The transcribed text.
    public let text: String
    
    /// Transcript segments with timing information.
    public let segments: [TranscriptionSegment]
    
    /// Detected or specified language.
    public let language: String?
    
    /// Duration of the audio in seconds.
    public let durationInSeconds: Double?
    
    /// Warnings from the provider.
    public let warnings: [TranscriptionWarning]
    
    /// Response metadata.
    public let responseMetadata: TranscriptionResponseMetadata
    
    /// Provider-specific metadata.
    public let providerMetadata: [String: String]?
    
    public init(
        text: String,
        segments: [TranscriptionSegment] = [],
        language: String? = nil,
        durationInSeconds: Double? = nil,
        warnings: [TranscriptionWarning] = [],
        responseMetadata: TranscriptionResponseMetadata,
        providerMetadata: [String: String]? = nil
    ) {
        self.text = text
        self.segments = segments
        self.language = language
        self.durationInSeconds = durationInSeconds
        self.warnings = warnings
        self.responseMetadata = responseMetadata
        self.providerMetadata = providerMetadata
    }
}