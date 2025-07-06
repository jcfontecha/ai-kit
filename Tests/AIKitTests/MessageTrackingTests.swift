import XCTest
@testable import AIKit

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
final class MessageTrackingTests: XCTestCase {
    
    // MARK: - StreamingMessageTracker Tests
    
    func testMessageTrackerAccumulatesText() async {
        let tracker = StreamingMessageTracker()
        
        await tracker.appendText("Hello")
        await tracker.appendText(" ")
        await tracker.appendText("world!")
        
        let text = await tracker.text
        XCTAssertEqual(text, "Hello world!")
        
        let hasContent = await tracker.hasContent
        XCTAssertTrue(hasContent)
    }
    
    func testMessageTrackerCreatesAssistantMessage() async {
        let tracker = StreamingMessageTracker(messageId: "test-123")
        
        await tracker.appendText("This is a response")
        
        let message = await tracker.assistantMessage
        XCTAssertNotNil(message)
        XCTAssertEqual(message?.role, .assistant)
        XCTAssertEqual(message?.id, "test-123")
        
        // Check content
        if case .text(let text)? = message?.content.first {
            XCTAssertEqual(text, "This is a response")
        } else {
            XCTFail("Expected text content")
        }
    }
    
    func testMessageTrackerHandlesToolCalls() async {
        let tracker = StreamingMessageTracker()
        
        // Add text and tool call
        await tracker.appendText("I'll search for that.")
        
        let toolCall = ToolCall(
            id: "call-123",
            function: ToolCallFunction(
                name: "search",
                arguments: "{\"query\":\"weather\"}"
            )
        )
        await tracker.addToolCall(toolCall)
        
        // Check tool calls
        let toolCalls = await tracker.toolCalls
        XCTAssertEqual(toolCalls.count, 1)
        XCTAssertEqual(toolCalls.first?.id, "call-123")
        
        // Check assistant message includes tool calls
        let message = await tracker.assistantMessage
        XCTAssertNotNil(message?.toolCalls)
        XCTAssertEqual(message?.toolCalls?.count, 1)
    }
    
    func testMessageTrackerHandlesToolResults() async {
        let tracker = StreamingMessageTracker()
        
        let toolResult = ToolResult(
            toolCallId: "call-123",
            result: .text("Weather is sunny")
        )
        await tracker.addToolResult(toolResult)
        
        // Tool results should be separate messages
        let messages = await tracker.allMessages
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.role, .tool)
        
        // Check tool result content
        if case .toolResult(let result)? = messages.first?.content.first {
            XCTAssertEqual(result.result.textValue, "Weather is sunny")
        } else {
            XCTFail("Expected tool result content")
        }
    }
    
    func testMessageTrackerResponseMessages() async {
        let tracker = StreamingMessageTracker()
        
        // Create a complete interaction
        await tracker.appendText("Let me search for that information.")
        
        let toolCall = ToolCall(
            id: "call-456",
            function: ToolCallFunction(
                name: "search_notes",
                arguments: "{\"query\":\"dance moves\"}"
            )
        )
        await tracker.addToolCall(toolCall)
        
        let toolResult = ToolResult(
            toolCallId: "call-456",
            result: .text("Found 5 notes about dance moves")
        )
        await tracker.addToolResult(toolResult)
        
        await tracker.finalize()
        
        // Check response messages
        let messages = await tracker.responseMessages
        XCTAssertEqual(messages.count, 2)
        
        // First message should be assistant with tool call
        XCTAssertEqual(messages[0].role, .assistant)
        XCTAssertNotNil(messages[0].toolCalls)
        
        // Second message should be tool result
        XCTAssertEqual(messages[1].role, .tool)
    }
    
    // MARK: - StreamTextResult Tests
    
    func testStreamTextResultResponseProperty() async throws {
        let provider = MockProvider()
        let model = provider.languageModel("test-model")
        let client = AIClient()
        
        let result = await client.streamText(model, prompt: "Hello")
        
        // Consume stream
        var streamedText = ""
        for try await chunk in result.textStream {
            streamedText += chunk.delta
        }
        
        // Test the new response property (Vercel-style)
        let response = await result.response
        
        // Verify response contains accumulated data
        XCTAssertEqual(response.text, streamedText)
        XCTAssertNotNil(response.finishReason)
        XCTAssertNotNil(response.usage)
        
        // Verify messages are properly formatted
        XCTAssertEqual(response.messages.count, 1)
        XCTAssertEqual(response.messages[0].role, .assistant)
        
        // Check that the message content matches streamed text
        let assistantMessage = response.messages[0]
        if case .text(let text) = assistantMessage.content.first {
            XCTAssertEqual(text, streamedText)
        } else {
            XCTFail("Expected text content in assistant message")
        }
    }
    
    func testStreamTextResultAccumulatesText() async throws {
        let provider = MockProvider()
        let model = provider.languageModel("test-model")
        let client = AIClient()
        
        let result = await client.streamText(model, prompt: "Say hello")
        
        // Consume stream
        var chunks: [String] = []
        var fullText = ""
        for try await chunk in result.textStream {
            if !chunk.delta.isEmpty {
                chunks.append(chunk.delta)
            }
            fullText += chunk.delta
        }
        
        XCTAssertFalse(chunks.isEmpty, "Should receive chunks")
        
        // Check accumulated text matches
        let text = await result.text
        XCTAssertEqual(text, fullText)
        
        // Check we have usage and finish reason
        let usage = await result.usage
        XCTAssertNotNil(usage)
        
        let finishReason = await result.finishReason
        XCTAssertNotNil(finishReason)
    }
    
    func testStreamTextResultConsistency() async throws {
        let provider = MockProvider()
        let model = provider.languageModel("test-model")
        let client = AIClient()
        
        let result = await client.streamText(model, prompt: "Test message tracking")
        
        // Consume stream and track chunks
        var streamedText = ""
        for try await chunk in result.textStream {
            streamedText += chunk.delta
        }
        
        // Verify all accumulated properties are consistent
        let finalText = await result.text
        let response = await result.response
        let messages = await result.messages
        
        // All text values should match
        XCTAssertEqual(finalText, streamedText)
        XCTAssertEqual(response.text, streamedText)
        
        // Messages should contain the accumulated text
        XCTAssertEqual(messages.count, 1)
        if case .text(let messageText) = messages[0].content.first {
            XCTAssertEqual(messageText, streamedText)
        }
        
        // Response messages should match direct messages access
        XCTAssertEqual(response.messages.count, messages.count)
        XCTAssertEqual(response.messages[0].role, messages[0].role)
    }
}

// MARK: - Test Helper Types

struct SearchParams: Codable, Sendable, SchemaProviding {
    let query: String
    
    static var schema: ObjectSchema<SearchParams> {
        .define(name: "SearchParams", description: "Search parameters") {
            Schema.string("query", required: true)
        }
    }
    
    typealias Partial = SearchParams
}

struct WeatherParams: Codable, Sendable, SchemaProviding {
    let location: String
    
    static var schema: ObjectSchema<WeatherParams> {
        .define(name: "WeatherParams", description: "Weather parameters") {
            Schema.string("location", required: true)
        }
    }
    
    typealias Partial = WeatherParams
}