import Foundation

// MARK: - Streaming Operations

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension AIClient {
    
    /// Stream text response from the given model and messages.
    ///
    /// This method provides real-time streaming of text generation:
    /// 1. Applies request middleware
    /// 2. Creates streaming connection to provider
    /// 3. Applies chunk middleware to each received chunk
    /// 4. Handles tool calls within the stream
    /// 5. Returns an AsyncThrowingStream of text chunks
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    /// - Returns: AsyncThrowingStream of `TextChunk` objects
    func streamText(_ model: LanguageModel, messages: [Message]) -> AsyncThrowingStream<TextChunk, Error> {
        // Minimal implementation to make tests pass - apply middleware, call provider, transform chunks
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // 1. Create provider request
                    let request = ProviderRequest(
                        modelId: model.modelId,
                        messages: messages,
                        configuration: model.configuration
                    )
                    
                    // 2. Apply request middleware
                    let processedRequest = try await applyRequestMiddleware(request)
                    
                    // 3. Stream from provider and transform to TextChunk
                    let providerStream = model.provider.streamTextRaw(processedRequest)
                    var accumulatedText = ""
                    
                    for try await providerChunk in providerStream {
                        accumulatedText += providerChunk.delta
                        
                        // Transform ProviderChunk to TextChunk
                        let textChunk = TextChunk(
                            delta: providerChunk.delta,
                            snapshot: accumulatedText,
                            finishReason: providerChunk.finishReason,
                            usage: providerChunk.usage,
                            chunkId: UUID().uuidString,
                            timestamp: Date(),
                            stepId: nil
                        )
                        
                        // 4. Apply chunk middleware and yield
                        let processedChunk = try await applyChunkMiddleware(textChunk)
                        continuation.yield(processedChunk)
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Stream text from a simple string prompt.
    ///
    /// This is a convenience method that wraps the prompt in a user message
    /// and calls the full `streamText` method.
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - prompt: The text prompt to send to the model
    /// - Returns: AsyncThrowingStream of `TextChunk` objects
    func streamText(_ model: LanguageModel, prompt: String) -> AsyncThrowingStream<TextChunk, Error> {
        let messages = [Message.user(prompt)]
        return streamText(model, messages: messages)
    }
    
    /// Stream structured object generation from the given model, messages, and schema.
    ///
    /// This method provides real-time streaming of structured object generation:
    /// 1. Applies request middleware
    /// 2. Validates the provided schema
    /// 3. Creates streaming connection with partial object parsing
    /// 4. Validates partial objects during generation
    /// 5. Returns an AsyncThrowingStream of object chunks
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    ///   - schema: The schema defining the structure of the expected object
    /// - Returns: AsyncThrowingStream of `ObjectChunk<T>` objects
    func streamObject<T: Codable>(_ model: LanguageModel, messages: [Message], schema: ObjectSchema<T>) -> AsyncThrowingStream<ObjectChunk<T>, Error> {
        // TODO: Implement streaming object generation with partial validation
        fatalError("AIClient.streamObject not implemented")
    }
}