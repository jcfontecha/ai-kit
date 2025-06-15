import Foundation

// MARK: - Middleware Operations

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension AIClient {
    
    /// Execute middleware chain for request transformation.
    ///
    /// This internal method applies all configured middleware to transform
    /// a request before sending it to the provider.
    ///
    /// - Parameter request: The request to transform
    /// - Returns: The transformed request
    /// - Throws: Any errors from middleware transformation
    func applyRequestMiddleware<T: AIRequest>(_ request: T) async throws -> T {
        if middleware.isEmpty {
            return request
        }
        
        // Create middleware chain and execute request transformation
        let chain = MiddlewareChain(middlewares: middleware)
        let context = MiddlewareContext(
            requestId: request.requestId,
            operationType: .generateText, // TODO: determine actual operation type
            modelId: "unknown", // TODO: extract from request context
            providerId: "unknown" // TODO: extract from provider
        )
        
        return try await chain.transformRequest(request, context: context)
    }
    
    /// Execute middleware chain for response transformation.
    ///
    /// This internal method applies all configured middleware to transform
    /// a response after receiving it from the provider.
    ///
    /// - Parameter response: The response to transform
    /// - Returns: The transformed response
    /// - Throws: Any errors from middleware transformation
    func applyResponseMiddleware<T: AIResponse>(_ response: T) async throws -> T {
        if middleware.isEmpty {
            return response
        }
        
        // Create middleware chain and execute response transformation
        let chain = MiddlewareChain(middlewares: middleware)
        let context = MiddlewareContext(
            requestId: response.responseId ?? "unknown",
            operationType: .generateText, // TODO: determine actual operation type
            modelId: "unknown", // TODO: extract from response context
            providerId: "unknown" // TODO: extract from provider
        )
        
        return try await chain.transformResponse(response, context: context)
    }
    
    /// Execute middleware chain for streaming chunk transformation.
    ///
    /// This internal method applies all configured middleware to transform
    /// each streaming chunk as it's received from the provider.
    ///
    /// - Parameter chunk: The chunk to transform
    /// - Returns: The transformed chunk
    /// - Throws: Any errors from middleware transformation
    func applyChunkMiddleware<T: StreamChunk>(_ chunk: T) async throws -> T {
        // TODO: Implement middleware chain execution
        return chunk
    }
}