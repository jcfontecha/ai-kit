import Foundation

// MARK: - AIClient + Transcription

/// Transcription functionality for AIClient.
///
/// This extension provides methods for audio transcription following the Vercel AI SDK pattern.
/// It integrates with the existing AIClient architecture, supporting middleware, error handling,
/// provider abstraction, and Swift's native Task cancellation.
///
/// ## Usage Examples
///
/// ### Basic Transcription
/// ```swift
/// let client = AIClient()
/// let model = provider.transcriptionModel("whisper-1")
/// let audio = AudioInput.fileURL(URL(fileURLWithPath: "audio.mp3"))
/// 
/// let response = try await client.transcribe(model: model, audio: audio)
/// print("Transcript: \(response.text)")
/// ```
///
/// ### Advanced Configuration
/// ```swift
/// let model = provider.transcriptionModel("whisper-1")
///     .language("en")
///     .prompt("Technical discussion about AI and machine learning")
///     .temperature(0.2)
///     .timestampGranularities([.word, .segment])
/// 
/// let response = try await client.transcribe(model: model, audio: audio)
/// 
/// for segment in response.segments {
///     print("\(segment.startSecond)s-\(segment.endSecond)s: \(segment.text)")
/// }
/// ```
///
/// ### Cancellation Support
/// ```swift
/// let task = Task {
///     try await client.transcribe(model: model, audio: audio)
/// }
/// 
/// // Cancel the transcription if needed
/// task.cancel()
/// 
/// do {
///     let result = try await task.value
///     print("Transcript: \(result.text)")
/// } catch is CancellationError {
///     print("Transcription was cancelled")
/// } catch {
///     print("Transcription failed: \(error)")
/// }
/// ```
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension AIClient {
    
    // MARK: - Primary Transcription Method
    
    /// Transcribe audio to text using the specified model.
    ///
    /// This is the main transcription method that mirrors the Vercel AI SDK's
    /// `experimental_transcribe` function. It supports all audio input types,
    /// configuration options, and provider-specific features.
    ///
    /// Uses Swift's native cancellation mechanism - the operation will be cancelled
    /// if the current Task is cancelled.
    ///
    /// - Parameters:
    ///   - model: The configured transcription model to use
    ///   - audio: The audio input to transcribe
    /// - Returns: A `TranscriptionResponse` containing the transcript and metadata
    /// - Throws: `TranscriptionError`, `CancellationError`, or provider-specific errors
    ///
    /// ## Usage with Cancellation
    /// ```swift
    /// let task = Task {
    ///     try await client.transcribe(model: model, audio: audio)
    /// }
    /// 
    /// // Cancel if needed
    /// task.cancel()
    /// ```
    ///
    /// ## Error Handling
    /// ```swift
    /// do {
    ///     let response = try await client.transcribe(model: model, audio: audio)
    ///     // Handle successful transcription
    /// } catch is CancellationError {
    ///     print("Transcription was cancelled")
    /// } catch TranscriptionError.noTranscriptGenerated(let reason) {
    ///     print("No transcript: \(reason)")
    /// } catch TranscriptionError.unsupportedAudioFormat(let format) {
    ///     print("Unsupported format: \(format)")
    /// } catch {
    ///     print("Transcription failed: \(error)")
    /// }
    /// ```
    func transcribe(
        model: TranscriptionModel,
        audio: AudioInput
    ) async throws -> TranscriptionResponse {
        
        // Validate the model configuration
        try model.validateConfiguration()
        
        // Create the provider request
        let request = model.createProviderRequest(audio: audio)
        
        // Apply middleware if any (for future extensibility)
        let processedRequest = try await applyMiddlewareToTranscriptionRequest(request)
        
        // Execute the transcription with proper error handling
        do {
            // Check for Swift's built-in cancellation
            try Task.checkCancellation()
            
            // Call the provider's transcription method
            let providerResponse = try await model.provider.transcribeRaw(processedRequest)
            
            // Apply middleware to response if any (for future extensibility)
            let processedResponse = try await applyMiddlewareToTranscriptionResponse(
                providerResponse, 
                request: processedRequest
            )
            
            // Convert provider response to public response
            let response = TranscriptionResponse(
                text: processedResponse.text,
                segments: processedResponse.segments,
                language: processedResponse.language,
                durationInSeconds: processedResponse.durationInSeconds,
                warnings: processedResponse.warnings,
                responses: [processedResponse.responseMetadata],
                providerMetadata: processedResponse.providerMetadata.map { providerData in
                    ["provider": providerData]
                }
            )
            
            return response
            
        } catch let error as TranscriptionError {
            // Re-throw transcription-specific errors
            throw error
        } catch let error as AIProviderError {
            // Convert provider errors to transcription errors
            throw convertProviderErrorToTranscriptionError(error)
        } catch {
            // Wrap other errors as provider-specific
            throw TranscriptionError.providerSpecific(
                "Transcription failed: \(error.localizedDescription)",
                underlyingError: error
            )
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Transcribe audio from a local file URL.
    ///
    /// Convenience method for transcribing local audio files without
    /// needing to manually create an AudioInput.
    ///
    /// - Parameters:
    ///   - model: The configured transcription model to use
    ///   - fileURL: Local file URL to the audio file
    /// - Returns: A `TranscriptionResponse` containing the transcript and metadata
    /// - Throws: `TranscriptionError`, `CancellationError`, or provider-specific errors
    func transcribe(
        model: TranscriptionModel,
        fileURL: URL
    ) async throws -> TranscriptionResponse {
        return try await transcribe(
            model: model,
            audio: .fileURL(fileURL)
        )
    }
    
    /// Transcribe audio from raw data.
    ///
    /// Convenience method for transcribing audio that's already loaded
    /// into memory as Data.
    ///
    /// - Parameters:
    ///   - model: The configured transcription model to use
    ///   - audioData: Raw audio data
    /// - Returns: A `TranscriptionResponse` containing the transcript and metadata
    /// - Throws: `TranscriptionError`, `CancellationError`, or provider-specific errors
    func transcribe(
        model: TranscriptionModel,
        audioData: Data
    ) async throws -> TranscriptionResponse {
        return try await transcribe(
            model: model,
            audio: .data(audioData)
        )
    }
    
    /// Transcribe audio from a remote URL.
    ///
    /// Convenience method for transcribing audio files hosted on remote servers.
    /// The audio will be downloaded as needed.
    ///
    /// - Parameters:
    ///   - model: The configured transcription model to use
    ///   - audioURL: Remote URL to the audio file
    /// - Returns: A `TranscriptionResponse` containing the transcript and metadata
    /// - Throws: `TranscriptionError`, `CancellationError`, or provider-specific errors
    func transcribe(
        model: TranscriptionModel,
        audioURL: URL
    ) async throws -> TranscriptionResponse {
        return try await transcribe(
            model: model,
            audio: .url(audioURL)
        )
    }
    
    // MARK: - Internal Middleware Support
    
    /// Apply middleware to transcription requests.
    ///
    /// This method provides a hook for applying middleware transformations
    /// to transcription requests. Currently a no-op but enables future
    /// middleware support for transcription.
    ///
    /// - Parameter request: The original transcription request
    /// - Returns: The processed transcription request
    /// - Throws: Middleware-specific errors
    private func applyMiddlewareToTranscriptionRequest(
        _ request: TranscriptionProviderRequest
    ) async throws -> TranscriptionProviderRequest {
        // For now, just return the request unchanged
        // In the future, this would apply middleware transformations
        return request
    }
    
    /// Apply middleware to transcription responses.
    ///
    /// This method provides a hook for applying middleware transformations
    /// to transcription responses. Currently a no-op but enables future
    /// middleware support for transcription.
    ///
    /// - Parameters:
    ///   - response: The original transcription response
    ///   - request: The associated request
    /// - Returns: The processed transcription response
    /// - Throws: Middleware-specific errors
    private func applyMiddlewareToTranscriptionResponse(
        _ response: TranscriptionProviderResponse,
        request: TranscriptionProviderRequest
    ) async throws -> TranscriptionProviderResponse {
        // For now, just return the response unchanged
        // In the future, this would apply middleware transformations
        return response
    }
    
    // MARK: - Error Conversion
    
    /// Convert provider errors to transcription-specific errors.
    ///
    /// This method translates generic provider errors into more specific
    /// transcription errors that provide better context for transcription failures.
    ///
    /// - Parameter error: The provider error to convert
    /// - Returns: A corresponding transcription error
    private func convertProviderErrorToTranscriptionError(_ error: AIProviderError) -> TranscriptionError {
        switch error {
        case .unsupportedModel(let model):
            return .unsupportedModel(model)
        case .unsupportedParameter(let param, let reason):
            return .invalidConfiguration("Unsupported parameter '\(param)': \(reason)")
        case .authenticationFailed(let reason):
            return .providerSpecific("Authentication failed: \(reason)", underlyingError: error)
        case .rateLimitExceeded(_):
            return .providerSpecific("Rate limit exceeded", underlyingError: error)
        case .invalidResponse(let reason):
            return .providerSpecific("Invalid response: \(reason)", underlyingError: error)
        case .networkError(let underlyingError):
            return .networkError(underlyingError)
        case .serviceUnavailable(let reason):
            return .providerSpecific("Service unavailable: \(reason)", underlyingError: error)
        case .providerSpecific(let message, let underlyingError):
            return .providerSpecific(message, underlyingError: underlyingError)
        }
    }
}


// MARK: - Future Middleware Support

/// Protocol for transcription middleware.
///
/// This protocol defines the interface for middleware that can intercept
/// and transform transcription requests and responses. This enables features
/// like caching, logging, metrics collection, and request/response modification.
///
/// Note: This is defined for future extensibility but not currently used.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public protocol TranscriptionMiddleware: Sendable {
    
    /// Transform a transcription request before it's sent to the provider.
    ///
    /// - Parameter request: The original request
    /// - Returns: The transformed request
    /// - Throws: Middleware-specific errors
    func processRequest(_ request: TranscriptionProviderRequest) async throws -> TranscriptionProviderRequest
    
    /// Transform a transcription response after it's received from the provider.
    ///
    /// - Parameters:
    ///   - response: The original response
    ///   - request: The associated request
    /// - Returns: The transformed response
    /// - Throws: Middleware-specific errors
    func processResponse(
        _ response: TranscriptionProviderResponse,
        for request: TranscriptionProviderRequest
    ) async throws -> TranscriptionProviderResponse
}