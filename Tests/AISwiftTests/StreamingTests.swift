import Testing
import Foundation
@testable import AISwift

@Test func testBasicStreaming() async throws {
    // Test basic streaming functionality using provider directly
    let provider = AISwift.mockProvider()
    
    let request = ProviderRequest(
        modelId: "mock-gpt-4",
        messages: [Message.user("Count to 5")],
        configuration: ModelConfiguration.default
    )
    
    // Test streaming
    let stream = provider.streamTextRaw(request)
    var chunks: [ProviderChunk] = []
    var fullContent = ""
    
    for try await chunk in stream {
        chunks.append(chunk)
        fullContent += chunk.delta
    }
    
    // Verify streaming behavior
    #expect(!chunks.isEmpty)
    #expect(!fullContent.isEmpty)
    
    // Verify last chunk has finish reason and usage
    let lastChunk = chunks.last!
    #expect(lastChunk.finishReason == .stop)
    #expect(lastChunk.usage != nil)
    #expect(lastChunk.usage!.totalTokens > 0)
    
    // Verify content accumulation
    #expect(fullContent.contains("Mock response"))
}

@Test func testStreamingErrorHandling() async throws {
    // Test streaming error handling using error-prone configuration
    let errorConfig = MockConfiguration(errorRate: 1.0) // 100% error rate
    let provider = MockProvider(apiKey: "test-key", configuration: errorConfig)
    
    let request = ProviderRequest(
        modelId: "mock-gpt-4",
        messages: [Message.user("This should trigger an error")],
        configuration: ModelConfiguration.default
    )
    
    // Test that streaming throws expected errors
    let stream = provider.streamTextRaw(request)
    
    do {
        for try await _ in stream {
            // Should not reach here with 100% error rate
            #expect(Bool(false), "Stream should have thrown an error")
        }
        #expect(Bool(false), "Stream should have thrown an error")
    } catch {
        // Verify we get the expected error type
        #expect(error is AIProviderError)
        if let providerError = error as? AIProviderError {
            switch providerError {
            case .serviceUnavailable(let message):
                #expect(message.contains("Simulated"))
            default:
                #expect(Bool(false), "Expected serviceUnavailable error")
            }
        }
    }
    
    // Test streaming with lower error rate (should sometimes succeed)
    let lowErrorConfig = MockConfiguration(errorRate: 0.0) // No errors
    let reliableProvider = MockProvider(apiKey: "test-key", configuration: lowErrorConfig)
    
    let reliableStream = reliableProvider.streamTextRaw(request)
    var receivedChunks = 0
    
    // This should succeed without errors
    for try await chunk in reliableStream {
        receivedChunks += 1
        #expect(!chunk.delta.isEmpty)
    }
    
    #expect(receivedChunks > 0)
}

@Test func testAIClientStreamText() async throws {
    // TRUE TDD: This test should FAIL first - AIClient.streamText not implemented
    let client = AISwift.client()
    let provider = AISwift.mockProvider()
    let model = provider.languageModel("mock-gpt-4")
    
    // This will fail until we implement AIClient.streamText
    let stream = await client.streamText(model, prompt: "Count to 5")
    
    var chunks: [TextChunk] = []
    var fullContent = ""
    
    for try await chunk in stream {
        chunks.append(chunk)
        fullContent += chunk.delta
    }
    
    // Verify streaming behavior once implemented
    #expect(!chunks.isEmpty)
    #expect(!fullContent.isEmpty)
    
    // Verify last chunk has proper finish state
    let lastChunk = chunks.last!
    #expect(lastChunk.finishReason == .stop)
    #expect(lastChunk.usage != nil)
    #expect(lastChunk.usage!.totalTokens > 0)
    
    // Verify accumulated content
    #expect(fullContent.contains("Mock response"))
}

@Test func testStreamTextBasicPattern() async throws {
    // Test basic streaming following Vercel AI SDK streamText pattern
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
        .temperature(0.0)
    
    // Test with simple prompt (Vercel pattern: streamText({ model, prompt }))
    let stream = await client.streamText(model, prompt: "Count from 1 to 5")
    
    var chunks: [TextChunk] = []
    var fullText = ""
    var finalUsage: TokenUsage? = nil
    var finalFinishReason: FinishReason? = nil
    
    // Collect all chunks (Vercel pattern: for await (const textPart of result.textStream))
    for try await chunk in stream {
        chunks.append(chunk)
        fullText += chunk.delta
        
        if let usage = chunk.usage {
            finalUsage = usage
        }
        
        if let finishReason = chunk.finishReason {
            finalFinishReason = finishReason
        }
    }
    
    // Verify streaming behavior matches Vercel AI SDK expectations
    #expect(!chunks.isEmpty, "Should receive streaming chunks")
    #expect(!fullText.isEmpty, "Should accumulate text content")
    #expect(finalUsage != nil, "Should have final usage information")
    #expect(finalFinishReason == .stop, "Should finish with stop reason")
    
    // Verify progressive streaming (chunks build up)
    var accumulatedSnapshot = ""
    for chunk in chunks {
        accumulatedSnapshot += chunk.delta
        #expect(chunk.snapshot.hasPrefix(accumulatedSnapshot) || chunk.snapshot == accumulatedSnapshot, 
               "Snapshot should contain accumulated text")
    }
    
    // Verify final content
    #expect(fullText.contains("Mock response"), "Should contain expected content")
    #expect(chunks.count > 5, "Should stream multiple chunks")
}

@Test func testStreamTextWithMessagesArray() async throws {
    // Test streaming with messages array (Vercel pattern: streamText({ model, messages }))
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
        .temperature(0.3)
    
    let messages = [
        Message.system("You are a helpful assistant that counts clearly."),
        Message.user("Count from 1 to 3"),
        Message.assistant("1, 2, 3"),
        Message.user("Now count from 4 to 6")
    ]
    
    let stream = await client.streamText(model, messages: messages)
    
    var chunks: [TextChunk] = []
    var hasContent = false
    
    for try await chunk in stream {
        chunks.append(chunk)
        if !chunk.delta.isEmpty {
            hasContent = true
        }
    }
    
    #expect(!chunks.isEmpty, "Should receive streaming chunks")
    #expect(hasContent, "Should have text content")
    
    // Verify last chunk has completion metadata
    let lastChunk = try #require(chunks.last)
    #expect(lastChunk.finishReason == .stop, "Should finish with stop")
    #expect(lastChunk.usage != nil, "Should have usage information")
}

@Test func testStreamTextWithToolCalls() async throws {
    // Test streaming with tool calls (Vercel pattern: streamText({ model, tools, prompt }))
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let weatherTool = Tool(
        function: ToolFunction(
            name: "get_weather",
            description: "Get current weather for a location",
            parameters: JSONSchema.object(properties: [
                "location": .string(),
                "unit": .string(enum: ["celsius", "fahrenheit"])
            ], required: ["location"])
        )
    )
    
    let stream = await client.streamText(
        model, 
        messages: [Message.user("What's the weather in San Francisco?")],
        tools: [weatherTool]
    )
    
    var chunks: [TextChunk] = []
    var toolCallStreamingStarts: [ToolCallStreamingStart] = []
    var toolCallDeltas: [ToolCallDelta] = []
    var completedToolCalls: [ToolCall] = []
    
    // Process stream and collect tool call events
    for try await chunk in stream {
        chunks.append(chunk)
        
        if let toolCallStart = chunk.toolCallStreamingStart {
            toolCallStreamingStarts.append(toolCallStart)
        }
        
        if let toolCallDelta = chunk.toolCallDelta {
            toolCallDeltas.append(toolCallDelta)
        }
        
        if let toolCalls = chunk.toolCalls {
            completedToolCalls.append(contentsOf: toolCalls)
        }
    }
    
    // Verify tool call streaming events (matching Vercel AI SDK tool call streaming)
    #expect(!toolCallStreamingStarts.isEmpty, "Should have tool call streaming start events")
    #expect(!toolCallDeltas.isEmpty, "Should have tool call argument deltas")
    #expect(!completedToolCalls.isEmpty, "Should have completed tool calls")
}

@Test func testStreamTextErrorHandling() async throws {
    // Test streaming error handling (Vercel pattern: onError callback)
    let errorConfig = MockConfiguration(errorRate: 1.0) // Force errors
    let provider = MockProvider(apiKey: "test", configuration: errorConfig)
    let model = provider.languageModel("gpt-4.1-nano")
    let client = AIClient()
    
    let stream = await client.streamText(model, prompt: "This should fail")
    
    do {
        for try await _ in stream {
            #expect(Bool(false), "Should not receive chunks when error rate is 100%")
        }
        #expect(Bool(false), "Should have thrown an error")
    } catch {
        #expect(error is AIProviderError, "Should throw AIProviderError")
    }
}

@Test func testStreamTextBackpressure() async throws {
    // Test that streaming respects backpressure (Vercel AI SDK behavior)
    let client = AIClient()
    let provider = MockProvider()
    let model = provider.languageModel("gpt-4.1-nano")
    
    let stream = await client.streamText(model, prompt: "Generate a long response")
    
    var chunkCount = 0
    let maxChunks = 5
    
    // Only consume first few chunks to test backpressure
    for try await _ in stream {
        chunkCount += 1
        if chunkCount >= maxChunks {
            break
        }
    }
    
    #expect(chunkCount == maxChunks, "Should respect early termination")
}