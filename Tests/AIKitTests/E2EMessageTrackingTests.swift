import XCTest
@testable import AIKit

/// End-to-end tests for automatic message tracking during streaming.
///
/// These tests verify that the message tracking feature works correctly
/// with real API providers, matching Vercel AI SDK's behavior.
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
final class E2EMessageTrackingTests: XCTestCase {
    
    
    // MARK: - OpenAI Tests
    
    func testOpenAIStreamingMessageTracking() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            return // Skip test if no API key
        }
        let provider = OpenAIProvider(apiKey: apiKey)
        let model = provider.languageModel("gpt-4.1-nano")
        let client = AIClient()
        
        let messages = [
            Message.system("You are a helpful assistant. Keep responses very brief."),
            Message.user("Say hello in 5 words or less.")
        ]
        
        let result = await client.streamText(model, messages: messages)
        
        // Consume the stream
        var streamedText = ""
        for try await chunk in result.textStream {
            streamedText += chunk.delta
        }
        
        // Test direct message access
        let responseMessages = await result.messages
        XCTAssertFalse(responseMessages.isEmpty)
        XCTAssertEqual(responseMessages.first?.role, .assistant)
        
        // Test response property (Vercel-style)
        let response = await result.response
        XCTAssertEqual(response.messages.count, responseMessages.count)
        XCTAssertEqual(response.text, streamedText)
        XCTAssertNotNil(response.usage)
        XCTAssertEqual(response.finishReason, FinishReason.stop)
        
        // Verify message content matches streamed text
        if let assistantMessage = response.messages.first,
           case .text(let messageText) = assistantMessage.content.first {
            XCTAssertEqual(messageText, streamedText)
        } else {
            XCTFail("Expected assistant message with text content")
        }
    }
    
    func testOpenAIStreamingWithToolCalls() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            return // Skip test if no API key
        }
        let provider = OpenAIProvider(apiKey: apiKey)
        let model = provider.languageModel("gpt-4.1-nano")
        let client = AIClient()
        
        // Define a simple tool
        let weatherTool = Tool(
            function: ToolFunction(
                name: "get_weather",
                description: "Get the weather for a location",
                parameters: JSONSchema.object(
                    properties: [
                        "location": .string()
                    ],
                    required: ["location"]
                )
            ),
            execute: { toolCall in
                // Parse the location from arguments
                if let data = toolCall.function.arguments.data(using: .utf8),
                   let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let location = args["location"] as? String {
                    return ToolResult(
                        toolCallId: toolCall.id,
                        result: .text("The weather in \(location) is sunny and 72°F")
                    )
                }
                return ToolResult(
                    toolCallId: toolCall.id,
                    result: .error("Invalid location")
                )
            }
        )
        
        let messages = [
            Message.system("You are a helpful assistant. Use the weather tool when asked about weather."),
            Message.user("What's the weather in San Francisco?")
        ]
        
        let result = await client.streamText(
            model,
            messages: messages,
            tools: [weatherTool],
            maxSteps: 2
        )
        
        // Consume the stream
        var fullText = ""
        var hasToolCalls = false
        var observedToolCallStart = false
        var observedToolCallDelta = false
        
        for try await chunk in result.textStream {
            fullText += chunk.delta
            if let toolCalls = chunk.toolCalls, !toolCalls.isEmpty {
                hasToolCalls = true
            }
            if chunk.toolCallStreamingStart != nil {
                observedToolCallStart = true
            }
            if chunk.toolCallDelta != nil {
                observedToolCallDelta = true
            }
        }
        
        // Verify tool was called
        XCTAssertTrue(hasToolCalls || fullText.contains("weather") || fullText.contains("San Francisco"))
        XCTAssertTrue(observedToolCallStart || observedToolCallDelta, "Expected OpenAI streaming tool call events to surface.")
        
        // Check response messages
        let response = await result.response
        
        // Should have at least one message
        XCTAssertFalse(response.messages.isEmpty)
        XCTAssertTrue(response.messages.contains(where: { $0.role == .tool }), "Expected a tool role message in the response.")
        
        // If tool was called, verify message structure
        if !response.toolCalls.isEmpty {
            // First message should be assistant with tool calls
            let assistantMessage = response.messages.first { $0.role == .assistant }
            XCTAssertNotNil(assistantMessage)
            XCTAssertNotNil(assistantMessage?.toolCalls)
            
            // Should have tool result messages if tools were executed
            let toolMessages = response.messages.filter { $0.role == .tool }
            if response.toolResults.count > 0 {
                XCTAssertFalse(toolMessages.isEmpty)
                let assistantMessages = response.messages.filter { $0.role == .assistant }
                XCTAssertGreaterThanOrEqual(assistantMessages.count, 2)
                XCTAssertTrue(assistantMessages.first?.toolCalls?.isEmpty == false)
                XCTAssertTrue((assistantMessages.last?.toolCalls?.isEmpty) ?? true)
            }
        }
        
        let recordedToolCalls = await result.toolCalls
        XCTAssertEqual(recordedToolCalls.count, response.toolCalls.count)
        if let arguments = recordedToolCalls.first?.function.arguments {
            XCTAssertTrue(arguments.contains("San Francisco"))
        }
        
        let recordedToolResults = await result.toolResults
        XCTAssertEqual(recordedToolResults.count, response.toolResults.count)
        if let firstResult = recordedToolResults.first?.result.textValue {
            XCTAssertTrue(firstResult.contains("San Francisco") || firstResult.contains("weather"))
        }
        
        let streamData = await result.streamDataValues
        XCTAssertTrue(streamData.isEmpty, "OpenAI should not emit stream data for this scenario.")
    }
    
    func testMessageAccumulationConsistency() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            return // Skip test if no API key
        }
        let provider = OpenAIProvider(apiKey: apiKey)
        let model = provider.languageModel("gpt-4.1-nano")
        let client = AIClient()
        
        let messages = [
            Message.user("Count from 1 to 3")
        ]
        
        let result = await client.streamText(model, messages: messages)
        
        // Track chunks
        var chunks: [String] = []
        var accumulatedFromChunks = ""
        
        for try await chunk in result.textStream {
            chunks.append(chunk.delta)
            accumulatedFromChunks += chunk.delta
        }
        
        // Get final accumulated values
        let finalText = await result.text
        let response = await result.response
        
        // Verify consistency
        XCTAssertEqual(finalText, accumulatedFromChunks)
        XCTAssertEqual(response.text, accumulatedFromChunks)
        
        // Verify message content matches
        if let assistantMessage = response.messages.first,
           case .text(let messageText) = assistantMessage.content.first {
            XCTAssertEqual(messageText, finalText)
        }
        
        // Verify we got multiple chunks (streaming worked)
        XCTAssertGreaterThan(chunks.count, 1, "Expected multiple chunks from streaming")
    }
}
