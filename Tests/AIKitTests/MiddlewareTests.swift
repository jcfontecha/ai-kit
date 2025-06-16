import Testing
import Foundation
@testable import AIKit

@Test func testMiddlewareChain() async throws {
    // Test that middleware chain is properly executed during text generation
    let provider = MockProvider()
    let model = LanguageModel(provider: provider, modelId: "test-model")
    
    // Create a middleware that modifies response text to verify it's being executed
    struct TextModifyingMiddleware: AIMiddleware {
        let id = "text-modifier"
        let name = "Text Modifying Middleware"
        let priority = 100
        
        func transformRequest<T: AIRequest>(_ request: T) async throws -> T {
            return request
        }
        
        func transformResponse<T: AIResponse>(_ response: T) async throws -> T {
            // Modify TextResponse by appending a marker
            if var textResponse = response as? TextResponse {
                let modifiedResponse = TextResponse(
                    text: textResponse.text + " [MIDDLEWARE_PROCESSED]",
                    finishReason: textResponse.finishReason,
                    usage: textResponse.usage,
                    messages: textResponse.messages,
                    steps: textResponse.steps,
                    responseId: textResponse.responseId,
                    modelId: textResponse.modelId,
                    timestamp: textResponse.timestamp,
                    warnings: textResponse.warnings,
                    responseHeaders: textResponse.responseHeaders
                )
                return modifiedResponse as! T
            }
            return response
        }
        
        func transformChunk<T: StreamChunk>(_ chunk: T) async throws -> T {
            return chunk
        }
        
        func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error {
            return error
        }
    }
    
    let middleware = TextModifyingMiddleware()
    let client = AIClient(middleware: [middleware])
    
    let messages = [Message.user("Hello, world!")]
    
    // This should execute the middleware chain and modify the response text
    let response = try await client.generateText(model, messages: messages)
    
    // Verify middleware was executed by checking for the marker
    #expect(response.text.contains("[MIDDLEWARE_PROCESSED]"), "Middleware should add marker to response text")
    #expect(response.usage.totalTokens > 0)
}

@Test func testMiddlewarePriority() async throws {
    // Test that middleware executes in correct priority order
    let provider = MockProvider()
    let model = LanguageModel(provider: provider, modelId: "test-model")
    
    // Create middleware with different priorities
    struct HighPriorityMiddleware: AIMiddleware {
        let id = "high-priority"
        let name = "High Priority Middleware"
        let priority = 200
        
        func transformRequest<T: AIRequest>(_ request: T) async throws -> T {
            return request
        }
        
        func transformResponse<T: AIResponse>(_ response: T) async throws -> T {
            if var textResponse = response as? TextResponse {
                let modifiedResponse = TextResponse(
                    text: "[HIGH]" + textResponse.text,
                    finishReason: textResponse.finishReason,
                    usage: textResponse.usage,
                    messages: textResponse.messages,
                    steps: textResponse.steps,
                    responseId: textResponse.responseId,
                    modelId: textResponse.modelId,
                    timestamp: textResponse.timestamp,
                    warnings: textResponse.warnings,
                    responseHeaders: textResponse.responseHeaders
                )
                return modifiedResponse as! T
            }
            return response
        }
        
        func transformChunk<T: StreamChunk>(_ chunk: T) async throws -> T {
            return chunk
        }
        
        func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error {
            return error
        }
    }
    
    struct LowPriorityMiddleware: AIMiddleware {
        let id = "low-priority"
        let name = "Low Priority Middleware"
        let priority = 50
        
        func transformRequest<T: AIRequest>(_ request: T) async throws -> T {
            return request
        }
        
        func transformResponse<T: AIResponse>(_ response: T) async throws -> T {
            if var textResponse = response as? TextResponse {
                let modifiedResponse = TextResponse(
                    text: textResponse.text + "[LOW]",
                    finishReason: textResponse.finishReason,
                    usage: textResponse.usage,
                    messages: textResponse.messages,
                    steps: textResponse.steps,
                    responseId: textResponse.responseId,
                    modelId: textResponse.modelId,
                    timestamp: textResponse.timestamp,
                    warnings: textResponse.warnings,
                    responseHeaders: textResponse.responseHeaders
                )
                return modifiedResponse as! T
            }
            return response
        }
        
        func transformChunk<T: StreamChunk>(_ chunk: T) async throws -> T {
            return chunk
        }
        
        func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error {
            return error
        }
    }
    
    let client = AIClient(middleware: [LowPriorityMiddleware(), HighPriorityMiddleware()])
    
    let messages = [Message.user("Test priority")]
    let response = try await client.generateText(model, messages: messages)
    
    // High priority should execute first, so [HIGH] should come before [LOW]
    #expect(response.text.hasPrefix("[HIGH]"), "High priority middleware should execute first")
    #expect(response.text.hasSuffix("[LOW]"), "Low priority middleware should execute last")
}

@Test func testMiddlewareStreamingTransform() async throws {
    // Test middleware transforms streaming chunks
    let provider = MockProvider()
    let model = LanguageModel(provider: provider, modelId: "test-model")
    
    struct ChunkModifyingMiddleware: AIMiddleware {
        let id = "chunk-modifier"
        let name = "Chunk Modifying Middleware"
        let priority = 100
        
        func transformRequest<T: AIRequest>(_ request: T) async throws -> T {
            return request
        }
        
        func transformResponse<T: AIResponse>(_ response: T) async throws -> T {
            return response
        }
        
        func transformChunk<T: StreamChunk>(_ chunk: T) async throws -> T {
            if var textChunk = chunk as? TextChunk {
                let modifiedChunk = TextChunk(
                    delta: "[" + textChunk.delta + "]",
                    snapshot: textChunk.snapshot,
                    finishReason: textChunk.finishReason,
                    usage: textChunk.usage,
                    toolCalls: textChunk.toolCalls,
                    toolCallStreamingStart: textChunk.toolCallStreamingStart,
                    toolCallDelta: textChunk.toolCallDelta
                )
                return modifiedChunk as! T
            }
            return chunk
        }
        
        func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error {
            return error
        }
    }
    
    let client = AIClient(middleware: [ChunkModifyingMiddleware()])
    
    let stream = await client.streamText(model, prompt: "Count to 3")
    var chunks: [TextChunk] = []
    
    for try await chunk in stream {
        chunks.append(chunk)
    }
    
    // Verify middleware modified chunks
    #expect(!chunks.isEmpty, "Should receive chunks")
    for chunk in chunks where !chunk.delta.isEmpty {
        #expect(chunk.delta.hasPrefix("["), "Delta should be wrapped with brackets")
        #expect(chunk.delta.hasSuffix("]"), "Delta should be wrapped with brackets")
    }
}

@Test func testMiddlewareErrorHandling() async throws {
    // Test middleware error handling capabilities (validation test)
    let provider = MockProvider()
    _ = LanguageModel(provider: provider, modelId: "test-model")
    
    struct ErrorHandlingMiddleware: AIMiddleware {
        let id = "error-handler"
        let name = "Error Handling Middleware"
        let priority = 100
        
        func transformRequest<T: AIRequest>(_ request: T) async throws -> T {
            return request
        }
        
        func transformResponse<T: AIResponse>(_ response: T) async throws -> T {
            return response
        }
        
        func transformChunk<T: StreamChunk>(_ chunk: T) async throws -> T {
            return chunk
        }
        
        func handleError(_ error: Error, context: MiddlewareContext) async throws -> Error {
            // Transform provider errors into middleware errors
            if error is AIProviderError {
                return AIMiddlewareError.middlewareExecutionFailed(
                    middlewareId: id,
                    error: error
                )
            }
            return error
        }
    }
    
    // Test that the middleware error handling method works in isolation
    let middleware = ErrorHandlingMiddleware()
    let originalError = AIProviderError.serviceUnavailable("Test error")
    let context = MiddlewareContext(
        requestId: "test",
        operationType: .generateText,
        modelId: "test-model",
        providerId: "test-provider"
    )
    
    let transformedError = try await middleware.handleError(originalError, context: context)
    
    if let middlewareError = transformedError as? AIMiddlewareError {
        switch middlewareError {
        case .middlewareExecutionFailed(let middlewareId, _):
            #expect(middlewareId == "error-handler", "Should transform error correctly")
        default:
            #expect(Bool(false), "Should be middlewareExecutionFailed error")
        }
    } else {
        #expect(Bool(false), "Should transform into AIMiddlewareError")
    }
    
    // Note: Full integration of middleware error handling with AIClient error flow
    // would require architectural changes to route all errors through middleware chain
}