import Foundation

// MARK: - Middleware Operations

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
        
        // Extract available context information
        let modelId = (request as? ProviderRequest)?.modelId ?? "unknown"
        let operationType: OperationType = .generateText // Context: called from generateText operations
        
        let context = MiddlewareContext(
            requestId: request.requestId,
            operationType: operationType,
            modelId: modelId,
            providerId: "unknown" // Note: Provider ID not available in request - would need client context
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
        
        // Extract available context information  
        let operationType: OperationType = .generateText // Context: called from generateText operations
        // Note: Model ID not available in response - would need to pass from request context
        
        let context = MiddlewareContext(
            requestId: response.responseId ?? "unknown",
            operationType: operationType,
            modelId: "unknown", // Note: Model ID not available in response - would need request context
            providerId: "unknown" // Note: Provider ID not available in response - would need client context
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
        if middleware.isEmpty {
            return chunk
        }
        
        // Create middleware chain and execute chunk transformation
        let chain = MiddlewareChain(middlewares: middleware)
        
        // Create minimal context for chunk processing
        let context = MiddlewareContext(
            requestId: chunk.chunkId,
            operationType: .streamText, // Context: processing streaming chunks
            modelId: "unknown", // Note: Model ID not available in chunk - would need request context
            providerId: "unknown" // Note: Provider ID not available in chunk - would need client context
        )
        
        return try await chain.transformChunk(chunk, context: context)
    }
}