import Foundation
@testable import AIKit

/// A simple mock provider for testing AIChat functionality
final class SimpleMockProvider: AIProvider, @unchecked Sendable {
    let name = "SimpleMockProvider"
    let supportedGenerationModes: Set<GenerationMode> = [.auto, .json, .tool]
    let defaultGenerationMode: GenerationMode = .auto
    
    // Mock responses storage
    @MainActor
    var mockResponses: [String: Result<ProviderResponse, Error>] = [:]
    @MainActor
    var mockStreamingResponses: [String: [ProviderChunk]] = [:]
    @MainActor
    var streamDelay: TimeInterval = 0
    
    func languageModel(_ modelId: String) -> LanguageModel {
        return LanguageModel(provider: self, modelId: modelId)
    }
    
    func validateConfiguration(_ configuration: ModelConfiguration) throws {
        // No validation needed for tests
    }
    
    @MainActor
    func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        // Simulate delay if needed
        if streamDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(streamDelay * 1_000_000_000))
        }
        
        // Return mock response if available
        if let mockResult = mockResponses[request.modelId] {
            switch mockResult {
            case .success(let response):
                return response
            case .failure(let error):
                throw error
            }
        }
        
        // Default response
        return ProviderResponse(
            content: "Default mock response",
            usage: Usage(promptTokens: 10, completionTokens: 5),
            finishReason: .stop
        )
    }
    
    func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                // Check for mock streaming responses
                if let chunks = mockStreamingResponses[request.modelId] {
                    for chunk in chunks {
                        if streamDelay > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(streamDelay * 1_000_000_000))
                        }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } else {
                    // Fall back to non-streaming response
                    do {
                        let response = try await generateTextRaw(request)
                        
                        // Convert response to chunks
                        if !response.content.isEmpty {
                            let words = response.content.split(separator: " ")
                            for (index, word) in words.enumerated() {
                                let delta = (index == 0 ? "" : " ") + String(word)
                                let isLast = index == words.count - 1
                                
                                let chunk = ProviderChunk(
                                    delta: delta,
                                    toolCall: nil,
                                    usage: isLast ? response.usage : nil,
                                    finishReason: isLast ? response.finishReason : nil
                                )
                                
                                if streamDelay > 0 {
                                    try? await Task.sleep(nanoseconds: UInt64(streamDelay * 1_000_000_000))
                                }
                                
                                continuation.yield(chunk)
                            }
                        }
                        
                        // Handle tool calls
                        if let toolCalls = response.toolCalls {
                            for toolCall in toolCalls {
                                let chunk = ProviderChunk(
                                    delta: "",
                                    toolCall: toolCall,
                                    usage: response.usage,
                                    finishReason: .toolCalls
                                )
                                continuation.yield(chunk)
                            }
                        }
                        
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
}

// Extension to make ProviderResponse initializer available
extension ProviderResponse {
    init(text: String, toolCalls: [ToolCall]? = nil, finishReason: FinishReason, usage: Usage? = nil) {
        self.init(
            content: text,
            toolCalls: toolCalls,
            usage: usage ?? Usage(promptTokens: 10, completionTokens: text.count / 4),
            finishReason: finishReason,
            providerMetadata: [:]
        )
    }
}

// Extension for ProviderChunk
extension ProviderChunk {
    init(text: String, finishReason: FinishReason?) {
        self.init(
            delta: text,
            toolCall: nil,
            usage: nil,
            finishReason: finishReason
        )
    }
}